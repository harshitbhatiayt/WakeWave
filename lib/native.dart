import 'package:flutter/services.dart';

/// Thin wrapper over the platform channel implemented in
/// ios/Runner/AlarmBridge.swift and android/.../AlarmBridge.kt.
class Native {
  static const _ch = MethodChannel('alarm101/native');

  /// {docs: app documents dir}
  static Future<Map<String, String>> paths() async {
    final m = await _ch.invokeMapMethod<String, String>('paths');
    return m ?? {};
  }

  /// Asks for alarm / notification permission. Returns true when granted.
  static Future<bool> requestPermission() async =>
      await _ch.invokeMethod<bool>('requestPermission') ?? false;

  /// Permission / capability status, e.g. {alarms: true, fullScreen: false}.
  static Future<Map<String, bool>> status() async {
    final m = await _ch.invokeMapMethod<String, bool>('status');
    return m ?? {};
  }

  /// Energy score (party ≈ 3, romantic ≈ 1.5) and hook start in seconds.
  static Future<({double score, double hook})?> analyze(String path) async {
    final m = await _ch.invokeMapMethod<String, double>('analyze', {'path': path});
    if (m == null) return null;
    return (score: m['score'] ?? 0, hook: m['hook'] ?? 0);
  }

  /// Turns a downloaded preview into something the OS alarm can play.
  /// iOS: converts to a <30 s .caf in Library/Sounds starting at [hook] and
  /// returns its file name. Android: returns the path unchanged (the hook is
  /// applied at playback).
  static Future<String> prepareSound(String src, String name, double hook) async =>
      await _ch.invokeMethod<String>('prepareSound', {'src': src, 'name': name, 'hook': hook}) ??
      '';

  /// Replaces every scheduled alarm with [items].
  /// Each item: {id, at (epoch ms), sound, hook, title, artist, art, url}.
  static Future<void> syncAlarms(List<Map<String, Object?>> items) =>
      _ch.invokeMethod('syncAlarms', {'items': items});

  /// Removes sound files that are no longer used. [keep] = names/paths to keep.
  static Future<void> cleanSounds(List<String> keep) =>
      _ch.invokeMethod('cleanSounds', {'keep': keep});

  static Future<void> playPreview(String path, {double start = 0}) =>
      _ch.invokeMethod('playPreview', {'path': path, 'start': start});
  static Future<void> stopPreview() => _ch.invokeMethod('stopPreview');

  static Future<bool> openUrl(String url) async =>
      await _ch.invokeMethod<bool>('openUrl', {'url': url}) ?? false;

  /// Id of the alarm whose "Full Song" button opened the app, if any.
  static Future<String?> consumeFired() => _ch.invokeMethod<String>('consumeFired');

  /// Opens the OS settings page for this app (to grant missing permissions).
  static Future<void> openSettings() => _ch.invokeMethod('openSettings');
}
