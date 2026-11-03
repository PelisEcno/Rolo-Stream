import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/services/hls_window.dart';

final base = Uri.parse('http://127.0.0.1:8888/proxy/hls/manifest.m3u8?d=x');

/// Con la misma forma que el manifiesto real de Zilla, ya reescrito por el proxy.
String playlist({int segments = 4, double seconds = 10}) => [
      '#EXTM3U',
      '#EXT-X-VERSION:7',
      '#EXT-X-TARGETDURATION:19',
      '#EXT-X-MEDIA-SEQUENCE:0',
      '#EXT-X-PLAYLIST-TYPE:VOD',
      '#EXT-X-MAP:URI="http://127.0.0.1:8888/proxy/hls/segment.html?d=init"',
      for (var i = 0; i < segments; i++) ...[
        '#EXTINF:$seconds,',
        'http://127.0.0.1:8888/proxy/hls/segment.html?d=$i',
      ],
      '#EXT-X-ENDLIST',
      '',
    ].join('\n');

void main() {
  group('parse', () {
    test('lee duración total y segmentos', () {
      final p = HlsPlaylist.parse(playlist(), base)!;
      expect(p.segmentCount, 4);
      expect(p.total, const Duration(seconds: 40));
    });

    test('duraciones decimales como las de Zilla', () {
      final text = playlist(segments: 2, seconds: 10.833333);
      expect(HlsPlaylist.parse(text, base)!.total.inMilliseconds, closeTo(21667, 1));
    });

    test('acepta saltos de línea CRLF', () {
      final p = HlsPlaylist.parse(playlist().replaceAll('\n', '\r\n'), base)!;
      expect(p.segmentCount, 4);
    });

    test('rechaza lo que no se puede abrir por tramos', () {
      expect(HlsPlaylist.parse('', base), isNull, reason: 'vacío');
      expect(HlsPlaylist.parse('<html>403</html>', base), isNull, reason: 'no es m3u8');
      expect(HlsPlaylist.parse(playlist().replaceAll('#EXT-X-ENDLIST', ''), base), isNull,
          reason: 'directo');
      expect(HlsPlaylist.parse('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1\nv.m3u8\n#EXT-X-ENDLIST', base),
          isNull,
          reason: 'maestro');
      expect(HlsPlaylist.parse('#EXTM3U\n#EXT-X-ENDLIST', base), isNull, reason: 'sin segmentos');
    });

    test('rechaza MAP o KEY a mitad del playlist, y BYTERANGE', () {
      final mid = playlist().replaceFirst(
          '#EXTINF:10.0,\nhttp://127.0.0.1:8888/proxy/hls/segment.html?d=2',
          '#EXT-X-MAP:URI="otro"\n#EXTINF:10.0,\nhttp://127.0.0.1:8888/proxy/hls/segment.html?d=2');
      expect(mid, isNot(playlist()));
      expect(HlsPlaylist.parse(mid, base), isNull);
      final range = playlist().replaceFirst('#EXTINF:10.0,', '#EXT-X-BYTERANGE:100@0\n#EXTINF:10.0,');
      expect(HlsPlaylist.parse(range, base), isNull);
    });

    test('resuelve rutas relativas de segmentos y del MAP', () {
      final p = HlsPlaylist.parse(
          '#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:5,\nseg0.m4s\n#EXT-X-ENDLIST\n',
          Uri.parse('http://h/a/list.m3u8'))!;
      final m = p.windowAt(Duration.zero).manifest;
      expect(m, contains('URI="http://h/a/init.mp4"'));
      expect(m, contains('\nhttp://h/a/seg0.m4s\n'));
    });
  });

  group('windowAt', () {
    late HlsPlaylist p;
    setUp(() => p = HlsPlaylist.parse(playlist(), base)!);

    List<String> segmentsOf(HlsWindow w) =>
        w.manifest.split('\n').where((l) => l.startsWith('http')).toList();

    test('desde 0 incluye todo', () {
      final w = p.windowAt(Duration.zero);
      expect(w.offset, Duration.zero);
      expect(segmentsOf(w).length, 4);
    });

    test('empieza en el segmento que contiene el punto, nunca después', () {
      final w = p.windowAt(const Duration(seconds: 25));
      expect(w.offset, const Duration(seconds: 20));
      expect(segmentsOf(w).first, endsWith('d=2'));
      expect(segmentsOf(w).length, 2);
    });

    test('justo en el borde empieza en ese segmento', () {
      expect(p.windowAt(const Duration(seconds: 30)).offset, const Duration(seconds: 30));
    });

    test('más allá del final se queda en el último', () {
      final w = p.windowAt(const Duration(hours: 2));
      expect(w.offset, const Duration(seconds: 30));
      expect(segmentsOf(w).length, 1);
    });

    test('conserva duración total, init, tipo y fin', () {
      final w = p.windowAt(const Duration(seconds: 25));
      expect(w.total, const Duration(seconds: 40));
      expect(w.manifest, startsWith('#EXTM3U\n'));
      expect(w.manifest, contains('#EXT-X-MAP:URI="http://127.0.0.1:8888/proxy/hls/segment.html?d=init"'));
      expect(w.manifest, contains('#EXT-X-PLAYLIST-TYPE:VOD'));
      expect(w.manifest.trim(), endsWith('#EXT-X-ENDLIST'));
    });

    test('el MAP va antes del primer segmento y la secuencia avanza', () {
      final m = p.windowAt(const Duration(seconds: 25)).manifest;
      expect(m, contains('#EXT-X-MEDIA-SEQUENCE:2'));
      expect(m.indexOf('#EXT-X-MAP'), lessThan(m.indexOf('#EXTINF')));
      expect(RegExp('#EXT-X-MEDIA-SEQUENCE').allMatches(m).length, 1);
    });

    test('el resultado se puede volver a leer con la duración restante', () {
      final w = p.windowAt(const Duration(seconds: 25));
      final again = HlsPlaylist.parse(w.manifest, base)!;
      expect(again.segmentCount, 2);
      expect(again.total, const Duration(seconds: 20));
    });
  });

  group('LocalManifestServer', () {
    Future<(int, String, String?)> get(String url) async {
      final client = HttpClient();
      try {
        final res = await (await client.getUrl(Uri.parse(url))).close();
        return (res.statusCode, await res.transform(utf8.decoder).join(), res.headers.contentType?.value);
      } finally {
        client.close(force: true);
      }
    }

    test('sirve el manifiesto por loopback, y se puede leer más de una vez', () async {
      final s = await LocalManifestServer.start('#EXTM3U\nhola');
      addTearDown(s.close);
      expect(s.url, startsWith('http://127.0.0.1:'));
      expect(s.url, endsWith('.m3u8'));
      final first = await get(s.url);
      expect(first.$1, 200);
      expect(first.$2, '#EXTM3U\nhola');
      expect(first.$3, 'application/vnd.apple.mpegurl');
      expect((await get(s.url)).$1, 200);
    });

    test('otras rutas no devuelven nada', () async {
      final s = await LocalManifestServer.start('secreto');
      addTearDown(s.close);
      final other = await get(Uri.parse(s.url).replace(path: '/otro/manifest.m3u8').toString());
      expect(other.$1, 404);
      expect(other.$2, isEmpty);
    });

    test('al cerrar deja de escuchar', () async {
      final s = await LocalManifestServer.start('x');
      final url = s.url;
      await s.close();
      await expectLater(get(url), throwsA(isA<SocketException>()));
    });
  });
}
