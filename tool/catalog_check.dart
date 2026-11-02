// Quick check: builds the song pool and resolves a few random songs.
import 'package:alarm101/catalog.dart';
import 'package:alarm101/models.dart';

Future<void> main() async {
  final pool = await fetchPool(Settings());
  print('pool: ${pool.length} songs');
  final sample = (pool.toList()..shuffle()).take(12);
  var ok = 0;
  for (final p in sample) {
    final s = await resolve(p);
    if (s != null) ok++;
    print('${p.cat.padRight(8)} ${p.title}  ->  ${s == null ? 'NONE' : (s.appleUrl != null ? 'itunes' : 'spotify-preview')}');
  }
  print('resolved $ok/12');
}
