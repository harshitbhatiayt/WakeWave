import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Public Spotify playlists the song pool is built from: trending charts plus
/// dance/party/workout lists. Slow songs that slip in are dropped by the
/// energy check in engine.dart.
const hindiPlaylists = [
  '37i9dQZF1DX0XUfTFmNBRM', // Hot Hits Hindi (Spotify, trending)
  '2O5Z4LSwxQq2PCd8ZuR0xD', // Latest Bollywood Hits 2026
  '3ba6w8ldKCmJN8IxI8ClXm', // Bollywood Party 2026
  '6Z6KXVZBhKR5IBvDizgiz4', // Hindi Party Songs (updated 2026)
  '37i9dQZF1DX8xfQRRX1PDm', // Bollywood Dance Music (Spotify)
  '19EoIAEoeScfYxbdkLcTSe', // Top 50 Bollywood Dance (Filtr India)
  '62STsAGVHka0Z74rG7W9e6', // Best Bollywood Workout (Filtr India)
];

const punjabiPlaylists = [
  '37i9dQZF1DWXVJK4aT7pmk', // Hot Hits Punjabi (Spotify, trending)
  '37i9dQZF1DX5cZuAHLNjGz', // Punjabi 101 (Spotify)
  '0uGeIUcnJViFVtrA6yTKdy', // Punjabi Bhangra 2026
  '03iFmM0MDAuNjGXLsHzQ3t', // Punjabi Bangers
  '6lg6RYySha8olyvMi7g4XY', // Decibel Presents: Punjabi
];

const englishPlaylists = [
  '37i9dQZF1DXcBWIGoYBM5M', // Today's Top Hits (Spotify, trending)
  '37i9dQZF1DX76Wlfdnj7AP', // Beast Mode (Spotify)
  '37i9dQZF1DWUVpAXiEPK8P', // Power Workout (Spotify)
  '37i9dQZF1DXdxcBWuJkbcy', // Gym Hits (Spotify)
  '37i9dQZF1DX32NsLKyzScr', // Power Hour (Spotify)
];

const _ua = {
  'User-Agent':
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148'
};

/// Extracts a playlist id from a Spotify URL, URI or bare id.
String? parsePlaylistId(String input) {
  final m = RegExp(r'playlist[/:]([A-Za-z0-9]{22})').firstMatch(input) ??
      RegExp(r'^([A-Za-z0-9]{22})$').firstMatch(input.trim());
  return m?.group(1);
}

/// Reads the track list of a public Spotify playlist from its embed page
/// (max 100 tracks, no login needed).
Future<List<PoolSong>> fetchPlaylist(String id, String cat) async {
  final res = await http
      .get(Uri.parse('https://open.spotify.com/embed/playlist/$id'), headers: _ua)
      .timeout(const Duration(seconds: 20));
  if (res.statusCode != 200) return [];
  final m = RegExp(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>',
          dotAll: true)
      .firstMatch(res.body);
  if (m == null) return [];
  final data = jsonDecode(m.group(1)!);
  final entity = data['props']?['pageProps']?['state']?['data']?['entity'];
  final list = (entity?['trackList'] as List?) ?? [];
  return [
    for (final t in list)
      if (t['uri'] is String && (t['isPlayable'] ?? true))
        PoolSong(
          (t['uri'] as String).split(':').last,
          t['title'] ?? '',
          (t['subtitle'] ?? '').toString().replaceAll(' ', ' '),
          cat,
          t['audioPreview']?['url'],
        ),
  ];
}

/// Name of a playlist (for showing custom playlists in settings).
Future<String?> playlistName(String id) async {
  try {
    final res = await http
        .get(Uri.parse('https://open.spotify.com/embed/playlist/$id'), headers: _ua)
        .timeout(const Duration(seconds: 20));
    return RegExp(r'"name":"([^"]+)"').firstMatch(res.body)?.group(1);
  } catch (_) {
    return null;
  }
}

/// Builds the full pool from every enabled playlist, deduplicated.
Future<List<PoolSong>> fetchPool(Settings s) async {
  final jobs = <Future<List<PoolSong>>>[
    if (s.hindi) for (final id in hindiPlaylists) _safe(fetchPlaylist(id, 'hindi')),
    if (s.punjabi) for (final id in punjabiPlaylists) _safe(fetchPlaylist(id, 'punjabi')),
    if (s.english) for (final id in englishPlaylists) _safe(fetchPlaylist(id, 'english')),
    for (final id in s.customPlaylists) _safe(fetchPlaylist(id, 'custom')),
  ];
  final seen = <String>{};
  final out = <PoolSong>[];
  for (final list in await Future.wait(jobs)) {
    for (final song in list) {
      if (seen.add(song.id)) out.add(song);
    }
  }
  return out;
}

Future<List<PoolSong>> _safe(Future<List<PoolSong>> f) async {
  try {
    return await f;
  } catch (_) {
    return [];
  }
}

/// "Gehra Hua (From "Dhurandhar")" -> "Gehra Hua"
String cleanTitle(String t) => t
    .split(RegExp(r'\s*[\(\[]\s*(From|from|feat|ft)'))
    .first
    .split(RegExp(r'\s+-\s+(From|from)'))
    .first
    .trim();

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// A pool song matched to its artwork + every preview we can get for it.
class Resolved {
  final String title;
  final String? artwork;
  final String? appleUrl;
  final List<String> previews; // iTunes, Spotify, or JioTune as a fallback

  Resolved(this.title, this.artwork, this.appleUrl, this.previews);
}

/// Looks the song up on Apple's public iTunes Search API for a 30 s preview
/// and artwork, and adds Spotify's own preview. The two previews usually cover
/// different parts of the song; the engine keeps the more upbeat one.
Future<Resolved?> resolve(PoolSong p) async {
  final title = cleanTitle(p.title);
  final firstArtist = p.artist.split(',').first.trim();
  final previews = <String>[];
  String? artwork, appleUrl;
  try {
    final uri = Uri.https('itunes.apple.com', '/search', {
      'term': '$title $firstArtist',
      'country': 'IN',
      'media': 'music',
      'entity': 'song',
      'limit': '5',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final results = (jsonDecode(res.body)['results'] as List?) ?? [];
      final want = _norm(title);
      for (final r in results) {
        final name = _norm(cleanTitle(r['trackName'] ?? ''));
        if (r['previewUrl'] == null || name.isEmpty || want.isEmpty) continue;
        if (name == want || name.startsWith(want) || want.startsWith(name)) {
          previews.add(r['previewUrl']);
          artwork = (r['artworkUrl100'] as String?)?.replaceAll('100x100', '600x600');
          appleUrl = r['trackViewUrl'];
          break;
        }
      }
    }
  } catch (_) {}
  if (p.spotifyPreview != null) previews.add(p.spotifyPreview!);
  if (previews.isEmpty) {
    // Many Hindi/Punjabi songs have no Apple/Spotify preview in India.
    final jt = await _jioTune(title, firstArtist);
    if (jt != null) {
      previews.add(jt.url);
      artwork ??= jt.artwork;
    }
  }
  if (previews.isEmpty) return null;
  artwork ??= await spotifyArt(p.id);
  return Resolved(title, artwork, appleUrl, previews);
}

/// JioSaavn's public JioTune clip (the 15 s caller-tune hook the label picked)
/// for a song, from its open search API. Only the unencrypted preview link is
/// used; full tracks stay on JioSaavn.
Future<({String url, String? artwork})?> _jioTune(String title, String artist) async {
  try {
    final uri = Uri.https('www.jiosaavn.com', '/api.php', {
      '__call': 'search.getResults',
      '_format': 'json',
      '_marker': '0',
      'api_version': '4',
      'ctx': 'web6dot0',
      'n': '5',
      'p': '1',
      'q': '$title $artist',
    });
    final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final results = (jsonDecode(res.body)['results'] as List?) ?? [];
    final want = _norm(title);
    for (final r in results) {
      final name = _norm(cleanTitle(r['title'] ?? ''));
      final url = r['more_info']?['vlink'];
      if (url is! String || url.isEmpty || name.isEmpty || want.isEmpty) continue;
      if (name == want || name.startsWith(want) || want.startsWith(name)) {
        final img = (r['image'] as String?)?.replaceAll('150x150', '500x500');
        return (url: url, artwork: img);
      }
    }
  } catch (_) {}
  return null;
}

/// Album art for a Spotify track from its public oEmbed endpoint (for songs
/// Apple doesn't have).
Future<String?> spotifyArt(String trackId) async {
  try {
    final uri = Uri.https('open.spotify.com', '/oembed', {'url': 'https://open.spotify.com/track/$trackId'});
    final res = await http.get(uri, headers: _ua).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    return jsonDecode(res.body)['thumbnail_url'] as String?;
  } catch (_) {
    return null;
  }
}
