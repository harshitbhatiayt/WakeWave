import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'catalog.dart' as catalog;
import 'models.dart';
import 'native.dart';

/// How far ahead songs are picked and alarms scheduled. Every ring gets its
/// own one-shot OS alarm with its own sound, so the app only has to be opened
/// once in this window to keep the songs fresh (no background work at night).
const lookahead = Duration(days: 7);
const _poolMaxAge = Duration(days: 3);

/// Bump when the playlists or song-picking rules change: refetches the pool
/// and re-picks every upcoming song.
const _dataVersion = 2;

/// Songs whose best preview scores below this are too slow for an alarm
/// (see Energy in AppDelegate.swift / Energy.kt).
const minEnergy = 1.95;

/// All app state + the scheduling logic. Persisted as one JSON file.
class Engine extends ChangeNotifier {
  late String _docs;
  List<AlarmItem> alarms = [];
  Settings settings = Settings();
  List<PoolSong> pool = [];
  DateTime? poolFetchedAt;
  List<Occurrence> upcoming = [];
  List<HistoryEntry> history = [];
  Set<String> lowEnergy = {};

  /// Downloaded songs that haven't rung yet and no ring is using (an alarm
  /// was edited, switched off or deleted). New rings take these first, so
  /// editing or toggling an alarm never downloads again. Every ring still gets
  /// its own song, and a song that rang is never put back here.
  List<Occurrence> stash = [];

  /// Rings whose song is still downloading. They are handed to the OS right
  /// away with a stand-in sound, so a ring a minute away never gets missed.
  Map<String, (String, DateTime)> _pending = {};

  bool busy = false;
  String? status; // short progress/error line for the UI
  Future<void>? _running;
  bool _again = false;

  File get _stateFile => File('$_docs/state.json');
  String get _previewDir => '$_docs/previews';

  Future<void> load() async {
    _docs = (await Native.paths())['docs']!;
    await Directory(_previewDir).create(recursive: true);
    if (await _stateFile.exists()) {
      try {
        final j = jsonDecode(await _stateFile.readAsString());
        alarms = [for (final a in j['alarms'] ?? []) AlarmItem.fromJson(a)];
        settings = Settings.fromJson(j['settings'] ?? {});
        pool = [for (final p in j['pool'] ?? []) PoolSong.fromJson(p)];
        poolFetchedAt = j['poolFetchedAt'] == null ? null : DateTime.parse(j['poolFetchedAt']);
        upcoming = [for (final o in j['upcoming'] ?? []) Occurrence.fromJson(o)];
        history = [for (final h in j['history'] ?? []) HistoryEntry.fromJson(h)];
        lowEnergy = Set<String>.from(j['lowEnergy'] ?? []);
        stash = [for (final o in j['stash'] ?? []) Occurrence.fromJson(o)];
        // iOS moves the app's data folder on every update: point saved
        // previews at the current one so they aren't downloaded again.
        for (final o in [...upcoming, ...stash]) {
          o.previewPath = '$_previewDir/${o.previewPath.split('/').last}';
        }
        if (j['version'] != _dataVersion) {
          poolFetchedAt = null;
          upcoming = [];
          stash = [];
        }
      } catch (e) {
        debugPrint('state load failed: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    await _stateFile.writeAsString(
      jsonEncode({
        'alarms': [for (final a in alarms) a.toJson()],
        'settings': settings.toJson(),
        'pool': [for (final p in pool) p.toJson()],
        'poolFetchedAt': poolFetchedAt?.toIso8601String(),
        'upcoming': [for (final o in upcoming) o.toJson()],
        'history': [for (final h in history) h.toJson()],
        'lowEnergy': lowEnergy.toList(),
        'stash': [for (final o in stash) o.toJson()],
        'version': _dataVersion,
      }),
    );
  }

  Occurrence? get next => upcoming.isEmpty ? null : upcoming.first;

  Occurrence? nextFor(String alarmId) {
    for (final o in upcoming) {
      if (o.alarmId == alarmId) return o;
    }
    return null;
  }

  // ---- user actions -------------------------------------------------------

  Future<void> saveAlarm(AlarmItem a) async {
    if (a.days.isEmpty && a.enabled) {
      a.onceAt = a.nextAfter(DateTime.now());
    }
    final i = alarms.indexWhere((x) => x.id == a.id);
    if (i >= 0) {
      alarms[i] = a;
    } else {
      alarms.add(a);
    }
    alarms.sort((x, y) => (x.hour * 60 + x.minute).compareTo(y.hour * 60 + y.minute));
    // Drop rings of the old version of this alarm (their songs go to the
    // stash); sync re-creates them.
    _release((o) => o.alarmId == a.id);
    await _save();
    notifyListeners();
    await sync();
  }

  Future<void> deleteAlarm(String id) async {
    alarms.removeWhere((a) => a.id == id);
    _release((o) => o.alarmId == id);
    await _save();
    notifyListeners();
    await sync();
  }

  Future<void> toggleAlarm(AlarmItem a, bool on) async {
    a.enabled = on;
    await saveAlarm(a);
  }

  Future<void> updateSettings(void Function(Settings) change, {bool refreshPool = false}) async {
    change(settings);
    if (refreshPool) poolFetchedAt = null;
    await _save();
    notifyListeners();
    if (refreshPool) await sync();
  }

  /// Picks a different song for one upcoming ring.
  Future<void> reshuffle(Occurrence o) async {
    final i = upcoming.indexWhere((x) => x.id == o.id);
    if (i < 0) return;
    final skip = {o.song.id};
    final fresh = await _assign(o.alarmId, o.at, skip: skip);
    if (fresh == null) {
      status = "Couldn't find another song. Check your connection.";
      notifyListeners();
      return;
    }
    upcoming[i] = fresh;
    await _pushToOs();
    await _save();
    notifyListeners();
  }

  // ---- scheduling ---------------------------------------------------------

  /// Makes sure every ring in the next [lookahead] has a fresh song, then
  /// hands the full list to the OS. Safe to call often.
  Future<void> sync() async {
    if (_running != null) {
      _again = true;
      return _running;
    }
    _running = _sync();
    try {
      await _running;
    } finally {
      _running = null;
    }
    if (_again) {
      _again = false;
      await sync();
    }
  }

  Future<void> _sync() async {
    busy = true;
    status = null;
    notifyListeners();
    try {
      final now = DateTime.now();

      // 1. Rings that already happened go to history.
      for (final o in upcoming.where((o) => !o.at.isAfter(now))) {
        history.insert(0, HistoryEntry(o.song, o.at));
      }
      upcoming.removeWhere((o) => !o.at.isAfter(now));
      history.removeWhere((h) => now.difference(h.at).inDays > 365);

      // One-time alarms switch themselves off after ringing.
      for (final a in alarms) {
        if (a.days.isEmpty && a.enabled && a.onceAt != null && !a.onceAt!.isAfter(now)) {
          a.enabled = false;
        }
      }

      // 2. Song pool.
      if (pool.isEmpty || poolFetchedAt == null || now.difference(poolFetchedAt!) > _poolMaxAge) {
        status = 'Fetching songs from Spotify playlists…';
        notifyListeners();
        final fresh = await catalog.fetchPool(settings);
        if (fresh.isNotEmpty) {
          pool = fresh;
          poolFetchedAt = now;
        }
      }

      // 3. Which rings should exist.
      final wanted = <String, (String, DateTime)>{};
      for (final a in alarms.where((a) => a.enabled)) {
        if (a.days.isEmpty) {
          final at = a.onceAt ?? a.nextAfter(now);
          if (at.isAfter(now)) wanted[_occId(a.id, at)] = (a.id, at);
          continue;
        }
        var t = now;
        while (true) {
          final at = a.nextAfter(t);
          if (at.difference(now) > lookahead) break;
          wanted[_occId(a.id, at)] = (a.id, at);
          t = at;
        }
      }
      upcoming.removeWhere((o) => !File(o.previewPath).existsSync());
      _release((o) => !wanted.containsKey(o.id));
      final rang = {for (final h in history) h.song.id};
      stash.removeWhere((o) => rang.contains(o.song.id) || !File(o.previewPath).existsSync());
      if (stash.length > 21) stash = stash.sublist(stash.length - 21);

      // 4. Pick songs for the new ones.
      final have = {for (final o in upcoming) o.id};
      final missing = wanted.entries.where((e) => !have.contains(e.key)).toList()
        ..sort((x, y) => x.value.$2.compareTo(y.value.$2));
      // Songs already on the phone first: an edited alarm gets its own songs
      // back (same day), then same day, then any. Only the rest download.
      final toFetch = <MapEntry<String, (String, DateTime)>>[];
      final rules = <bool Function(Occurrence, String, DateTime)>[
        (o, id, at) => o.alarmId == id && _dayKey(o.at) == _dayKey(at),
        (o, id, at) => _dayKey(o.at) == _dayKey(at),
        (o, id, at) => true,
      ];
      var left = missing;
      for (final rule in rules) {
        final next = <MapEntry<String, (String, DateTime)>>[];
        for (final e in left) {
          final (alarmId, at) = e.value;
          final from = stash.where((o) => rule(o, alarmId, at)).firstOrNull;
          if (from == null) {
            next.add(e);
            continue;
          }
          stash.remove(from);
          upcoming.add(Occurrence(
            id: e.key,
            alarmId: alarmId,
            at: at,
            song: from.song,
            sound: from.sound,
            previewPath: from.previewPath,
          ));
        }
        left = next;
      }
      toFetch.addAll(left);
      upcoming.sort((x, y) => x.at.compareTo(y.at));
      _pending = {for (final e in toFetch) e.key: e.value};
      await _pushToOs();
      var done = 0;
      for (final e in toFetch) {
        status = 'Preparing songs… ${++done}/${toFetch.length}';
        notifyListeners();
        final o = await _assign(e.value.$1, e.value.$2);
        _pending.remove(e.key);
        if (o != null) {
          upcoming.add(o);
          upcoming.sort((x, y) => x.at.compareTo(y.at));
          // Hand each ring to the OS as soon as it is ready, so an alarm set
          // a minute from now isn't waiting for the whole week's songs.
          await _pushToOs();
          await _save();
          notifyListeners();
        }
      }
      upcoming.sort((x, y) => x.at.compareTo(y.at));

      // Posters for songs picked before Spotify art was looked up.
      for (final o in [...upcoming, ...stash, ...history.take(10)]) {
        final song = o is HistoryEntry ? o.song : (o as Occurrence).song;
        if (song.artwork != null) continue;
        final art = await catalog.spotifyArt(song.id);
        if (art == null) continue;
        final withArt = Song(
          id: song.id,
          title: song.title,
          artist: song.artist,
          previewUrl: song.previewUrl,
          artwork: art,
          appleUrl: song.appleUrl,
          hook: song.hook,
          energy: song.energy,
        );
        if (o is Occurrence) o.song = withArt;
        if (o is HistoryEntry) history[history.indexOf(o)] = HistoryEntry(withArt, o.at);
      }

      // 5. Hand everything to the OS.
      await _pushToOs();
      await _cleanup();
      final failed = wanted.length - upcoming.length;
      status = failed > 0 ? '$failed alarms have no song yet. Open the app when online.' : null;
    } catch (e) {
      status = 'Sync error: $e';
    } finally {
      if (_pending.isNotEmpty) {
        _pending = {};
        await _pushToOs();
      }
      busy = false;
      await _save();
      notifyListeners();
    }
  }

  String _occId(String alarmId, DateTime at) =>
      '${alarmId}_${at.year}${_pad(at.month)}${_pad(at.day)}${_pad(at.hour)}${_pad(at.minute)}';
  String _dayKey(DateTime d) => '${d.year}${_pad(d.month)}${_pad(d.day)}';

  /// Takes rings out of [upcoming] and keeps their unrung songs for reuse.
  void _release(bool Function(Occurrence) test) {
    for (final o in upcoming.where(test)) {
      if (!stash.any((x) => x.song.id == o.song.id)) stash.add(o);
    }
    upcoming.removeWhere(test);
  }
  String _pad(int n) => n.toString().padLeft(2, '0');

  /// Songs that must not be picked now: rang within repeatDays, or already
  /// lined up for another ring.
  Set<String> _blocked() {
    final cutoff = DateTime.now().subtract(Duration(days: settings.repeatDays));
    return {
      for (final h in history)
        if (h.at.isAfter(cutoff)) h.song.id,
      for (final o in upcoming) o.song.id,
      for (final o in stash) o.song.id,
    };
  }

  Future<Occurrence?> _assign(String alarmId, DateTime at, {Set<String> skip = const {}}) async {
    final blocked = _blocked()..addAll(skip);
    final allowed = pool.where(
      (p) =>
          !lowEnergy.contains(p.id) &&
          ((p.cat == 'custom') ||
              (p.cat == 'hindi' && settings.hindi) ||
              (p.cat == 'punjabi' && settings.punjabi) ||
              (p.cat == 'english' && settings.english)),
    );
    var candidates = allowed.where((p) => !blocked.contains(p.id)).toList();
    if (candidates.isEmpty) {
      // Pool exhausted for this repeat window: fall back to the songs that
      // rang longest ago.
      final recent = {
        for (final o in upcoming) o.song.id,
        for (final o in stash) o.song.id,
        ...skip,
      };
      candidates = allowed.where((p) => !recent.contains(p.id)).toList();
    }
    candidates.shuffle(Random());
    final id = _occId(alarmId, at);
    for (final p in candidates.take(20)) {
      try {
        final r = await catalog.resolve(p);
        if (r == null) continue;

        // Download every preview, keep the most upbeat one.
        ({String path, String url, double score, double hook})? best;
        for (var i = 0; i < r.previews.length; i++) {
          final url = r.previews[i];
          final ext = url.contains('scdn.co') || Uri.parse(url).path.endsWith('.mp3')
              ? 'mp3'
              : 'm4a';
          final path = '$_previewDir/${p.id}_$i.$ext';
          final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200 || res.bodyBytes.length < 20000) continue;
          await File(path).writeAsBytes(res.bodyBytes);
          final a = await Native.analyze(path);
          if (a != null && (best == null || a.score > best.score)) {
            if (best != null) File(best.path).deleteSync();
            best = (path: path, url: url, score: a.score, hook: a.hook);
          } else {
            File(path).deleteSync();
          }
        }
        if (best == null) continue;
        if (best.score < minEnergy) {
          lowEnergy.add(p.id); // slow/romantic: never pick it again
          File(best.path).deleteSync();
          continue;
        }
        final path = '$_previewDir/${p.id}.${best.path.split('.').last}';
        File(best.path).renameSync(path);

        final song = Song(
          id: p.id,
          title: r.title,
          artist: p.artist,
          previewUrl: best.url,
          artwork: r.artwork,
          appleUrl: r.appleUrl,
          hook: best.hook,
          energy: best.score,
        );
        // Unique per song: iOS may cache alarm sounds by file name.
        final sound = await Native.prepareSound(path, 'a101_${song.id}', song.hook);
        if (sound.isEmpty) continue;
        return Occurrence(
          id: id,
          alarmId: alarmId,
          at: at,
          song: song,
          sound: sound,
          previewPath: path,
        );
      } catch (e) {
        debugPrint('prepare ${p.title} failed: $e');
      }
    }
    return null;
  }

  Future<void> _pushToOs() {
    // Stand-in for rings still downloading: any song already prepared,
    // else the system alarm sound.
    final spare = stash.firstOrNull ?? upcoming.firstOrNull;
    return Native.syncAlarms([
      for (final o in upcoming)
        {
          'id': o.id,
          'at': o.at.millisecondsSinceEpoch,
          'sound': o.sound,
          'hook': o.song.hook,
          'title': o.song.title,
          'artist': o.song.artist,
          'art': o.song.artwork ?? '',
          'url': settings.player.urlFor(o.song),
        },
      for (final e in _pending.entries)
        if (!upcoming.any((o) => o.id == e.key))
          {
            'id': e.key,
            'at': e.value.$2.millisecondsSinceEpoch,
            'sound': spare?.sound ?? '',
            'hook': spare?.song.hook ?? 0,
            'title': spare?.song.title ?? 'Wake up',
            'artist': spare?.song.artist ?? '',
            'art': spare?.song.artwork ?? '',
            'url': spare == null ? '' : settings.player.urlFor(spare.song),
          },
    ]);
  }

  Future<void> _cleanup() async {
    await Native.cleanSounds([
      for (final o in upcoming) o.sound,
      for (final o in stash) o.sound,
    ]);
    final keep = {
      for (final o in upcoming) o.previewPath,
      for (final o in stash) o.previewPath,
    };
    // Keep the last few days of history previews so they can still be replayed.
    for (final h in history.take(5)) {
      for (final ext in ['m4a', 'mp3']) {
        keep.add('$_previewDir/${h.song.id}.$ext');
      }
    }
    for (final f in Directory(_previewDir).listSync().whereType<File>()) {
      if (!keep.contains(f.path)) f.deleteSync();
    }
  }

  /// Local preview for a song if it is still on disk.
  String? previewFor(Song s) {
    for (final ext in ['m4a', 'mp3']) {
      final p = '$_previewDir/${s.id}.$ext';
      if (File(p).existsSync()) return p;
    }
    return null;
  }

  /// The ring whose alarm screen button opened the app.
  Occurrence? findRing(String id) {
    for (final o in upcoming) {
      if (o.id == id) return o;
    }
    for (final h in history) {
      // Already moved to history by a sync.
      if (id.endsWith(_occId('', h.at))) {
        return Occurrence(
          id: id,
          alarmId: '',
          at: h.at,
          song: h.song,
          sound: '',
          previewPath: previewFor(h.song) ?? '',
        );
      }
    }
    return null;
  }
}
