import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'catalog.dart' show parsePlaylistId, playlistName;
import 'engine.dart';
import 'models.dart';
import 'native.dart';

final engine = Engine();

// ---- design tokens ---------------------------------------------------------

const _ink = Color(0xFF07060B);
const _orange = Color(0xFFFF8A1F);
const _pink = Color(0xFFFF3B6B);
const _violet = Color(0xFF7B5CFF);
const _text2 = Color(0x99FFFFFF); // secondary label
const _text3 = Color(0x59FFFFFF); // tertiary label
const _grad = LinearGradient(colors: [_orange, _pink]);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Alarm101());
}

class Alarm101 extends StatelessWidget {
  const Alarm101({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WakeWave',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _ink,
        colorScheme: ColorScheme.fromSeed(
            seedColor: _orange, brightness: Brightness.dark, primary: _orange),
        cupertinoOverrideTheme:
            const CupertinoThemeData(brightness: Brightness.dark, primaryColor: _orange),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      home: const HomePage(),
    );
  }
}

// ---- helpers ---------------------------------------------------------------

String fmtTime(int h, int m) {
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh:${m.toString().padLeft(2, '0')}';
}

String amPm(int h) => h < 12 ? 'AM' : 'PM';

const _dayShort = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String daysText(List<int> d) {
  final s = d.toSet();
  if (s.isEmpty) return 'Once';
  if (s.length == 7) return 'Every day';
  if (s.length == 5 && s.containsAll([1, 2, 3, 4, 5])) return 'Weekdays';
  if (s.length == 2 && s.containsAll([6, 7])) return 'Weekends';
  return (s.toList()..sort()).map((x) => _dayShort[x]).join(' ');
}

String whenText(DateTime at) {
  final now = DateTime.now();
  final diff = DateTime(at.year, at.month, at.day)
      .difference(DateTime(now.year, now.month, now.day))
      .inDays;
  final t = '${fmtTime(at.hour, at.minute)} ${amPm(at.hour)}';
  if (diff == 0) return 'Today, $t';
  if (diff == 1) return 'Tomorrow, $t';
  if (diff == -1) return 'Yesterday, $t';
  if (diff < -1) return '${at.day} ${_month[at.month]}, $t';
  return '${_dayShort[at.weekday]}, $t';
}

const _month = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// ---- glass building blocks -------------------------------------------------

/// Dark canvas with soft colour glows, so the frosted glass has something to blur.
class Backdrop extends StatelessWidget {
  final Widget child;
  const Backdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    Widget glow(Color c, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
        );
    return Stack(children: [
      const Positioned.fill(child: ColoredBox(color: _ink)),
      Positioned.fill(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
          child: Stack(children: [
            Positioned(top: -120, left: -80, child: glow(_orange.withValues(alpha: .55), 340)),
            Positioned(top: 180, right: -140, child: glow(_pink.withValues(alpha: .45), 360)),
            Positioned(bottom: -160, left: -60, child: glow(_violet.withValues(alpha: .45), 380)),
          ]),
        ),
      ),
      Positioned.fill(child: child),
    ]);
  }
}

/// Frosted "liquid glass" surface.
class Glass extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double tint;
  const Glass({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = const EdgeInsets.all(16),
    this.tint = .07,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: r,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: tint + .06),
                Colors.white.withValues(alpha: tint - .03),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .14), width: .8),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Round glass icon button (like the toolbar buttons in iOS 26 apps).
class GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final bool filled;
  const GlassIcon({super.key, required this.icon, this.onTap, this.size = 44, this.filled = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: filled ? _grad : null,
              color: filled ? null : Colors.white.withValues(alpha: .10),
              border: Border.all(color: Colors.white.withValues(alpha: .16), width: .8),
            ),
            child: Icon(icon,
                size: size * .46,
                color: onTap == null ? Colors.white30 : Colors.white),
          ),
        ),
      ),
    );
  }
}

class _Artwork extends StatelessWidget {
  final String? url;
  final double size;
  const _Artwork(this.url, {this.size = 84});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(gradient: _grad),
      child: Icon(CupertinoIcons.music_note_2, size: size * .45, color: Colors.white),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .18),
      child: url == null
          ? fallback
          : Image.network(url!,
              width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

Route<T> _route<T>(Widget page) => CupertinoPageRoute<T>(builder: (_) => page);

// ---- home ------------------------------------------------------------------

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  bool _loaded = false;
  String? _playing; // song id of the preview playing in-app
  bool _permOk = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    engine.addListener(_onEngine);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    engine.removeListener(_onEngine);
    super.dispose();
  }

  void _onEngine() => mounted ? setState(() {}) : null;

  Future<void> _start() async {
    await engine.load();
    setState(() => _loaded = true);
    _permOk = await Native.requestPermission();
    setState(() {});
    await _checkFired();
    await engine.sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && _loaded) {
      _checkFired();
      engine.sync();
      Native.status().then((m) => setState(() => _permOk = m['alarms'] ?? true));
    }
  }

  /// Opened from the alarm's "Full Song" button.
  Future<void> _checkFired() async {
    final id = await Native.consumeFired();
    if (id == null || !mounted) return;
    final ring = engine.findRing(id);
    if (ring == null) return;
    if (engine.settings.autoOpen) {
      await Native.openUrl(engine.settings.player.urlFor(ring.song));
    }
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _FiredSheet(song: ring.song),
    );
  }

  Future<void> _togglePreview(Song s, String? path) async {
    if (_playing == s.id) {
      await Native.stopPreview();
      setState(() => _playing = null);
    } else if (path != null) {
      await Native.playPreview(path, start: s.hook);
      setState(() => _playing = s.id);
    }
  }

  Future<void> _edit([AlarmItem? a]) async {
    final res = await showModalBottomSheet<AlarmItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AlarmEditor(alarm: a),
    );
    if (res != null) await engine.saveAlarm(res);
  }

  @override
  Widget build(BuildContext context) {
    final next = engine.next;
    return Scaffold(
      // Add button sits at the bottom, in thumb reach.
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _loaded
          ? Container(
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                BoxShadow(color: _orange.withValues(alpha: .45), blurRadius: 24, offset: const Offset(0, 8)),
              ]),
              child: GlassIcon(icon: CupertinoIcons.add, filled: true, size: 64, onTap: () => _edit()),
            )
          : null,
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: !_loaded
              ? const Center(child: CupertinoActivityIndicator())
              : RefreshIndicator(
                  onRefresh: engine.sync,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    children: [
                      Row(children: [
                        GlassIcon(
                          icon: CupertinoIcons.clock,
                          onTap: () => Navigator.push(
                              context, _route(HistoryPage(onPlay: _togglePreview))),
                        ),
                        const Spacer(),
                        GlassIcon(
                          icon: CupertinoIcons.slider_horizontal_3,
                          onTap: () => Navigator.push(context, _route(const SettingsPage())),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      const Text('Alarms',
                          style: TextStyle(
                              fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -.8)),
                      const Text('A new upbeat song every morning.',
                          style: TextStyle(fontSize: 15, color: _text2)),
                      const SizedBox(height: 20),
                      if (!_permOk)
                        _Notice(
                          icon: CupertinoIcons.exclamationmark_triangle_fill,
                          text: "Alarm permission is off, so alarms can't ring.",
                          action: 'Allow',
                          onTap: Native.openSettings,
                        ),
                      // Only real downloads/errors show here; a quick re-sync
                      // (toggle, edit) shouldn't make the list jump.
                      if (engine.status != null)
                        _Notice(
                          icon: engine.busy ? null : CupertinoIcons.info_circle_fill,
                          text: engine.status ?? 'Syncing…',
                        ),
                      if (next != null)
                        _NextSongCard(
                          ring: next,
                          playing: _playing == next.song.id,
                          onPlay: () => _togglePreview(next.song, next.previewPath),
                          onShuffle: engine.busy ? null : () => engine.reshuffle(next),
                          onFull: () =>
                              Native.openUrl(engine.settings.player.urlFor(next.song)),
                        )
                      else if (engine.alarms.isEmpty)
                        _Empty(onAdd: () => _edit()),
                      if (engine.alarms.isNotEmpty) ...[
                        const SizedBox(height: 26),
                        const _SectionLabel('Your alarms'),
                        for (final a in engine.alarms)
                          _AlarmRow(alarm: a, onTap: () => _edit(a)),
                      ],
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 6, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 13, letterSpacing: .6, fontWeight: FontWeight.w600, color: _text3)),
      );
}

class _Notice extends StatelessWidget {
  final IconData? icon;
  final String text;
  final String? action;
  final VoidCallback? onTap;
  const _Notice({this.icon, required this.text, this.action, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          icon == null
              ? const CupertinoActivityIndicator(radius: 9)
              : Icon(icon, size: 18, color: _orange),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
          if (action != null)
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 30),
              onPressed: onTap,
              child: Text(action!, style: const TextStyle(color: _orange, fontSize: 15)),
            ),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final VoidCallback onAdd;
  const _Empty({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Glass(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 28),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _grad),
          child: const Icon(CupertinoIcons.alarm_fill, size: 34, color: Colors.white),
        ),
        const SizedBox(height: 18),
        const Text('No alarms yet',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        const Text('Set one and wake up to a different\nHindi, Punjabi or English banger every day.',
            textAlign: TextAlign.center, style: TextStyle(color: _text2, height: 1.35)),
        const SizedBox(height: 22),
        _PillButton(label: 'Add Alarm', icon: CupertinoIcons.add, onTap: onAdd, gradient: true),
      ]),
    );
  }
}

/// Capsule button: white (primary) or gradient.
class _PillButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool gradient;
  const _PillButton({required this.label, this.icon, this.onTap, this.gradient = false});

  @override
  Widget build(BuildContext context) {
    final fg = gradient ? Colors.white : _ink;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: gradient ? _grad : null,
          color: gradient ? null : Colors.white,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _NextSongCard extends StatelessWidget {
  final Occurrence ring;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback? onShuffle;
  final VoidCallback onFull;
  const _NextSongCard({
    required this.ring,
    required this.playing,
    required this.onPlay,
    required this.onShuffle,
    required this.onFull,
  });

  @override
  Widget build(BuildContext context) {
    final s = ring.song;
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: Stack(children: [
        // Album art, heavily blurred, tints the card like Apple Music's now-playing.
        if (s.artwork != null)
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: Image.network(s.artwork!,
                  fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
          ),
        Glass(
          radius: 30,
          tint: .06,
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(CupertinoIcons.alarm, size: 15, color: _text2),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Next alarm · ${whenText(ring.at)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: _text2)),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              _Artwork(s.artwork, size: 88),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.3)),
                  const SizedBox(height: 3),
                  Text(s.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, color: _text2)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.bolt_fill, size: 12, color: _orange),
                      SizedBox(width: 4),
                      Text('High energy',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600, color: _orange)),
                    ]),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              GlassIcon(
                icon: playing ? CupertinoIcons.stop_fill : CupertinoIcons.play_fill,
                onTap: onPlay,
                size: 50,
              ),
              const SizedBox(width: 10),
              GlassIcon(icon: CupertinoIcons.shuffle, onTap: onShuffle, size: 50),
              const SizedBox(width: 12),
              Expanded(
                child: _PillButton(
                  label: 'Listen on ${engine.settings.player.label}',
                  icon: CupertinoIcons.arrow_up_right,
                  onTap: onFull,
                ),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _AlarmRow extends StatelessWidget {
  final AlarmItem alarm;
  final VoidCallback onTap;
  const _AlarmRow({required this.alarm, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = alarm;
    final ring = engine.nextFor(a.id);
    final on = a.enabled;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey(a.id),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 26),
          decoration: BoxDecoration(
              color: const Color(0xFFFF3B30), borderRadius: BorderRadius.circular(26)),
          child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        onDismissed: (_) => engine.deleteAlarm(a.id),
        child: GestureDetector(
          onTap: onTap,
          child: Glass(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(fmtTime(a.hour, a.minute),
                          style: TextStyle(
                              fontSize: 54,
                              fontWeight: FontWeight.w200,
                              letterSpacing: -1.5,
                              color: on ? Colors.white : _text3)),
                      const SizedBox(width: 4),
                      Text(amPm(a.hour),
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w300,
                              color: on ? Colors.white : _text3)),
                    ],
                  ),
                  Text(daysText(a.days),
                      style: TextStyle(fontSize: 14, color: on ? _text2 : _text3)),
                  if (on && ring != null) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(CupertinoIcons.music_note, size: 13, color: _orange),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(ring.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, color: _orange)),
                      ),
                    ]),
                  ],
                ]),
              ),
              CupertinoSwitch(
                value: on,
                activeTrackColor: _orange,
                onChanged: (v) => engine.toggleAlarm(a, v),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---- alarm editor ----------------------------------------------------------

class AlarmEditor extends StatefulWidget {
  final AlarmItem? alarm;
  const AlarmEditor({super.key, this.alarm});

  @override
  State<AlarmEditor> createState() => _AlarmEditorState();
}

class _AlarmEditorState extends State<AlarmEditor> {
  late DateTime _time;
  late Set<int> _days;

  @override
  void initState() {
    super.initState();
    final a = widget.alarm;
    final now = DateTime.now();
    _time = DateTime(now.year, now.month, now.day, a?.hour ?? 6, a?.minute ?? 30);
    _days = a == null ? {1, 2, 3, 4, 5, 6, 7} : a.days.toSet();
  }

  void _save() => Navigator.pop(
        context,
        AlarmItem(
          id: widget.alarm?.id ?? AlarmItem.newId(),
          hour: _time.hour,
          minute: _time.minute,
          days: _days.toList()..sort(),
          enabled: true,
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Glass(
        radius: 34,
        tint: .10,
        padding: EdgeInsets.zero,
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
              width: 38,
              height: 5,
              decoration:
                  BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(children: [
                CupertinoButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: _text2)),
                ),
                Expanded(
                  child: Text(widget.alarm == null ? 'Add Alarm' : 'Edit Alarm',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                ),
                CupertinoButton(
                  onPressed: _save,
                  child: const Text('Save',
                      style: TextStyle(color: _orange, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            SizedBox(
              height: 216,
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  brightness: Brightness.dark,
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(fontSize: 26, color: Colors.white),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.time,
                  initialDateTime: _time,
                  onDateTimeChanged: (t) => _time = t,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Glass(
                radius: 20,
                tint: .05,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('Repeat', style: TextStyle(fontSize: 16)),
                    const Spacer(),
                    Text(daysText(_days.toList()),
                        style: const TextStyle(fontSize: 15, color: _text2)),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    for (var d = 1; d <= 7; d++)
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: d == 1 ? 0 : 6),
                          child: _DayChip(
                            label: _dayShort[d],
                            on: _days.contains(d),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _days.contains(d) ? _days.remove(d) : _days.add(d));
                            },
                          ),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
            if (widget.alarm != null)
              CupertinoButton(
                onPressed: () {
                  engine.deleteAlarm(widget.alarm!.id);
                  Navigator.pop(context);
                },
                child: const Text('Delete Alarm', style: TextStyle(color: Color(0xFFFF453A))),
              )
            else
              const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }
}

/// One weekday in the Repeat picker: a small glass tile, lit orange when on.
class _DayChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _DayChip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: on
                ? [_orange.withValues(alpha: .36), _orange.withValues(alpha: .16)]
                : [Colors.white.withValues(alpha: .07), Colors.white.withValues(alpha: .03)],
          ),
          border: Border.all(
            color: on ? _orange.withValues(alpha: .85) : Colors.white.withValues(alpha: .10),
            width: on ? 1.1 : .8,
          ),
          boxShadow: on
              ? [BoxShadow(color: _orange.withValues(alpha: .28), blurRadius: 14, spreadRadius: -2)]
              : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 200),
          style: DefaultTextStyle.of(context).style.copyWith(
            fontSize: 13,
            letterSpacing: .2,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? Colors.white : _text3,
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

// ---- fired sheet -----------------------------------------------------------

class _FiredSheet extends StatelessWidget {
  final Song song;
  const _FiredSheet({required this.song});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Glass(
        radius: 34,
        tint: .10,
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Good morning',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            _Artwork(song.artwork, size: 150),
            const SizedBox(height: 14),
            Text(song.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            Text(song.artist,
                textAlign: TextAlign.center, style: const TextStyle(color: _text2)),
            const SizedBox(height: 20),
            const Align(alignment: Alignment.centerLeft, child: _SectionLabel('Listen on')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in Player.values)
                GestureDetector(
                  onTap: () => Native.openUrl(p.urlFor(song)),
                  child: Glass(
                    radius: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ---- shared page scaffold ---------------------------------------------------

/// Pushed page with a back button and a large title, on the glow backdrop.
class _Page extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Page({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 48), children: [
            Align(
              alignment: Alignment.centerLeft,
              child: GlassIcon(
                  icon: CupertinoIcons.chevron_back, onTap: () => Navigator.pop(context)),
            ),
            const SizedBox(height: 18),
            Text(title,
                style: const TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -.8)),
            const SizedBox(height: 18),
            ...children,
          ]),
        ),
      ),
    );
  }
}

/// iOS "inset grouped" section made of glass.
class _Group extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> rows;
  const _Group({this.header, this.footer, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (header != null) _SectionLabel(header!),
        Glass(
          radius: 22,
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Divider(height: .5, thickness: .5, color: Colors.white.withValues(alpha: .12)),
                ),
              rows[i],
            ],
          ]),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
            child: Text(footer!, style: const TextStyle(fontSize: 13, color: _text3, height: 1.35)),
          ),
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Row({this.leading, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16)),
                if (subtitle != null)
                  Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _text2)),
              ]),
            ),
            ?trailing,
          ]),
        ),
      ),
    );
  }
}

Widget _switch(bool v, ValueChanged<bool> f) =>
    CupertinoSwitch(value: v, activeTrackColor: _orange, onChanged: f);

// ---- history ---------------------------------------------------------------

class HistoryPage extends StatelessWidget {
  final Future<void> Function(Song, String?) onPlay;
  const HistoryPage({super.key, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        Widget row(Song song, DateTime at) => _Row(
              leading: _Artwork(song.artwork, size: 46),
              title: song.title,
              subtitle: '${whenText(at)} · ${song.artist}',
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: () => Native.openUrl(engine.settings.player.urlFor(song)),
                child: const Icon(CupertinoIcons.arrow_up_right_circle_fill, color: _orange),
              ),
              onTap: () => onPlay(song, engine.previewFor(song)),
            );
        return _Page(title: 'History', children: [
          if (engine.upcoming.isNotEmpty)
            _Group(header: 'Up next', rows: [
              for (final o in engine.upcoming.take(7)) row(o.song, o.at),
            ]),
          if (engine.history.isNotEmpty)
            _Group(header: 'Played', rows: [
              for (final h in engine.history) row(h.song, h.at),
            ])
          else
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                  child: Text('No songs played yet.', style: TextStyle(color: _text2))),
            ),
        ]);
      },
    );
  }
}

// ---- settings --------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _names = <String, String>{};

  @override
  void initState() {
    super.initState();
    for (final id in engine.settings.customPlaylists) {
      playlistName(id).then((n) => mounted ? setState(() => _names[id] = n ?? id) : null);
    }
  }

  Future<void> _addPlaylist() async {
    final ctl = TextEditingController();
    final url = await showCupertinoDialog<String>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: const Text('Add Spotify Playlist'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctl,
            autofocus: true,
            placeholder: 'https://open.spotify.com/playlist/…',
          ),
        ),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, ctl.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final id = url == null ? null : parsePlaylistId(url);
    if (id == null) {
      if (url != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("That doesn't look like a Spotify playlist link.")));
      }
      return;
    }
    if (engine.settings.customPlaylists.contains(id)) return;
    await engine.updateSettings((s) => s.customPlaylists.add(id), refreshPool: true);
    final n = await playlistName(id);
    if (mounted) setState(() => _names[id] = n ?? id);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: engine,
      builder: (context, _) {
        final s = engine.settings;
        return _Page(title: 'Settings', children: [
          _Group(
            header: 'Music',
            footer: 'Songs come from trending and party playlists. '
                'Slow songs are filtered out automatically.',
            rows: [
              _Row(
                title: 'Hindi / Bollywood',
                trailing: _switch(s.hindi,
                    (v) => engine.updateSettings((s) => s.hindi = v, refreshPool: true)),
              ),
              _Row(
                title: 'Punjabi',
                trailing: _switch(s.punjabi,
                    (v) => engine.updateSettings((s) => s.punjabi = v, refreshPool: true)),
              ),
              _Row(
                title: 'English',
                trailing: _switch(s.english,
                    (v) => engine.updateSettings((s) => s.english = v, refreshPool: true)),
              ),
              _Row(
                title: '${engine.pool.length} songs in the pool',
                subtitle: engine.poolFetchedAt == null
                    ? 'Not loaded yet'
                    : 'Updated ${whenText(engine.poolFetchedAt!)}',
                trailing: engine.busy
                    ? const CupertinoActivityIndicator()
                    : CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 36),
                        onPressed: () => engine.updateSettings((_) {}, refreshPool: true),
                        child: const Icon(CupertinoIcons.arrow_clockwise, color: _orange),
                      ),
              ),
            ],
          ),
          _Group(
            header: 'No repeats',
            footer: 'A song can play again only after this many days.',
            rows: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Text('Repeat gap', style: TextStyle(fontSize: 16)),
                    const Spacer(),
                    Text('${s.repeatDays} days',
                        style: const TextStyle(fontSize: 16, color: _text2)),
                  ]),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoSlider(
                      min: 7,
                      max: 90,
                      divisions: 83,
                      activeColor: _orange,
                      value: s.repeatDays.toDouble(),
                      onChanged: (v) => engine.updateSettings((s) => s.repeatDays = v.round()),
                    ),
                  ),
                ]),
              ),
            ],
          ),
          _Group(
            header: 'Play full song on',
            rows: [
              for (final p in Player.values)
                _Row(
                  title: p.label,
                  trailing: s.player == p
                      ? const Icon(CupertinoIcons.checkmark_alt, color: _orange)
                      : null,
                  onTap: () => engine.updateSettings((s) => s.player = p),
                ),
            ],
          ),
          _Group(
            footer: 'Tapping "Full Song" on the alarm opens the song in the app above.',
            rows: [
              _Row(
                title: 'Open full song from alarm',
                trailing: _switch(s.autoOpen, (v) => engine.updateSettings((s) => s.autoOpen = v)),
              ),
            ],
          ),
          _Group(
            header: 'Your Spotify playlists',
            rows: [
              for (final id in s.customPlaylists)
                _Row(
                  leading: const Icon(CupertinoIcons.music_note_list, color: _orange),
                  title: _names[id] ?? id,
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: () =>
                        engine.updateSettings((s) => s.customPlaylists.remove(id), refreshPool: true),
                    child: const Icon(CupertinoIcons.minus_circle_fill, color: Color(0xFFFF453A)),
                  ),
                ),
              _Row(
                leading: const Icon(CupertinoIcons.add_circled_solid, color: _orange),
                title: 'Add a public playlist',
                onTap: _addPlaylist,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Each alarm plays the most upbeat 30-second part of the song '
              '(official Apple / Spotify previews). The app prepares songs for the '
              'next 7 days whenever you open it, so open it at least once a week.',
              style: TextStyle(fontSize: 13, color: _text3, height: 1.35),
            ),
          ),
        ]);
      },
    );
  }
}
