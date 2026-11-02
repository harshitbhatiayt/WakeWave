import 'dart:math';

/// One alarm as the user sets it up.
class AlarmItem {
  String id;
  int hour;
  int minute;

  /// DateTime.weekday values (1 = Mon … 7 = Sun). Empty = rings once.
  List<int> days;
  bool enabled;

  /// For a one-time alarm: the moment it should ring.
  DateTime? onceAt;

  AlarmItem({
    required this.id,
    required this.hour,
    required this.minute,
    this.days = const [],
    this.enabled = true,
    this.onceAt,
  });

  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch}${Random().nextInt(999)}';

  /// Next ring time strictly after [from].
  DateTime nextAfter(DateTime from) {
    var d = DateTime(from.year, from.month, from.day, hour, minute);
    if (!d.isAfter(from)) d = d.add(const Duration(days: 1));
    if (days.isEmpty) return d;
    while (!days.contains(d.weekday)) {
      d = d.add(const Duration(days: 1));
    }
    return d;
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'days': days,
        'enabled': enabled,
        'onceAt': onceAt?.toIso8601String(),
      };

  factory AlarmItem.fromJson(Map<String, dynamic> j) => AlarmItem(
        id: j['id'],
        hour: j['hour'],
        minute: j['minute'],
        days: List<int>.from(j['days'] ?? []),
        enabled: j['enabled'] ?? true,
        onceAt: j['onceAt'] == null ? null : DateTime.parse(j['onceAt']),
      );
}

/// A track from one of the Spotify playlists (the song pool).
class PoolSong {
  final String id; // Spotify track id
  final String title;
  final String artist;
  final String cat; // hindi | punjabi | english | custom
  final String? spotifyPreview;

  PoolSong(this.id, this.title, this.artist, this.cat, this.spotifyPreview);

  Map<String, Object?> toJson() =>
      {'id': id, 'title': title, 'artist': artist, 'cat': cat, 'sp': spotifyPreview};

  factory PoolSong.fromJson(Map<String, dynamic> j) =>
      PoolSong(j['id'], j['title'], j['artist'], j['cat'], j['sp']);
}

/// A pool song with its playable preview + artwork resolved.
class Song {
  final String id;
  final String title;
  final String artist;
  final String previewUrl;
  final String? artwork;
  final String? appleUrl;
  final double hook; // seconds into the preview where the punchiest part starts
  final double energy;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.previewUrl,
    this.artwork,
    this.appleUrl,
    this.hook = 0,
    this.energy = 0,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'previewUrl': previewUrl,
        'artwork': artwork,
        'appleUrl': appleUrl,
        'hook': hook,
        'energy': energy,
      };

  factory Song.fromJson(Map<String, dynamic> j) => Song(
        id: j['id'],
        title: j['title'],
        artist: j['artist'],
        previewUrl: j['previewUrl'],
        artwork: j['artwork'],
        appleUrl: j['appleUrl'],
        hook: (j['hook'] ?? 0).toDouble(),
        energy: (j['energy'] ?? 0).toDouble(),
      );
}

/// One concrete ring (alarm X on date Y) with the song picked for it.
class Occurrence {
  final String id;
  final String alarmId;
  final DateTime at;
  Song song;
  String sound; // iOS: file name in Library/Sounds; Android: file path
  String previewPath; // local preview file for in-app playback

  Occurrence({
    required this.id,
    required this.alarmId,
    required this.at,
    required this.song,
    required this.sound,
    required this.previewPath,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'alarmId': alarmId,
        'at': at.toIso8601String(),
        'song': song.toJson(),
        'sound': sound,
        'previewPath': previewPath,
      };

  factory Occurrence.fromJson(Map<String, dynamic> j) => Occurrence(
        id: j['id'],
        alarmId: j['alarmId'],
        at: DateTime.parse(j['at']),
        song: Song.fromJson(j['song']),
        sound: j['sound'],
        previewPath: j['previewPath'],
      );
}

/// A song that already rang.
class HistoryEntry {
  final Song song;
  final DateTime at;

  HistoryEntry(this.song, this.at);

  Map<String, Object?> toJson() => {'song': song.toJson(), 'at': at.toIso8601String()};

  factory HistoryEntry.fromJson(Map<String, dynamic> j) =>
      HistoryEntry(Song.fromJson(j['song']), DateTime.parse(j['at']));
}

/// Apps the user can pick for playing the full song.
enum Player {
  spotify('Spotify'),
  youtubeMusic('YouTube Music'),
  youtube('YouTube'),
  jiosaavn('JioSaavn'),
  appleMusic('Apple Music');

  final String label;
  const Player(this.label);

  String urlFor(Song s) {
    final q = Uri.encodeComponent('${s.title} ${s.artist.split(',').first}');
    switch (this) {
      case Player.spotify:
        return 'https://open.spotify.com/track/${s.id}';
      case Player.youtubeMusic:
        return 'https://music.youtube.com/search?q=$q';
      case Player.youtube:
        return 'https://www.youtube.com/results?search_query=$q';
      case Player.jiosaavn:
        return 'https://www.jiosaavn.com/search/song/$q';
      case Player.appleMusic:
        return s.appleUrl ?? 'https://music.apple.com/in/search?term=$q';
    }
  }
}

class Settings {
  bool hindi;
  bool punjabi;
  bool english;
  int repeatDays;
  Player player;
  bool autoOpen; // open the full song right after "Full Song" on the alarm
  List<String> customPlaylists; // Spotify playlist ids

  Settings({
    this.hindi = true,
    this.punjabi = true,
    this.english = false,
    this.repeatDays = 30,
    this.player = Player.spotify,
    this.autoOpen = true,
    List<String>? customPlaylists,
  }) : customPlaylists = customPlaylists ?? [];

  Map<String, Object?> toJson() => {
        'hindi': hindi,
        'punjabi': punjabi,
        'english': english,
        'repeatDays': repeatDays,
        'player': player.name,
        'autoOpen': autoOpen,
        'customPlaylists': customPlaylists,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings(
        hindi: j['hindi'] ?? true,
        punjabi: j['punjabi'] ?? true,
        english: j['english'] ?? false,
        repeatDays: j['repeatDays'] ?? 30,
        player: Player.values.firstWhere((p) => p.name == j['player'],
            orElse: () => Player.spotify),
        autoOpen: j['autoOpen'] ?? true,
        customPlaylists: List<String>.from(j['customPlaylists'] ?? []),
      );
}
