import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Parte de un playlist HLS que empieza en un segmento dado.
class HlsWindow {
  /// Tiempo real del episodio en el que empieza el manifiesto.
  final Duration offset;

  /// Duración real del episodio completo.
  final Duration total;
  final String manifest;
  const HlsWindow({required this.offset, required this.total, required this.manifest});
}

class _Segment {
  final Duration start;
  final List<String> lines;
  const _Segment(this.start, this.lines);
}

/// Playlist HLS bajo demanda que se puede abrir desde cualquier segmento.
///
/// En algunos HLS fMP4, FFmpeg se queda clavado al saltar a un segmento que aún no ha cargado, sobre
/// todo con AV1. Empezar directamente en ese segmento no requiere ningún salto.
class HlsPlaylist {
  final List<String> _header;
  final List<_Segment> _segments;
  final Duration total;
  final int _firstSequence;

  HlsPlaylist._(this._header, this._segments, this.total, this._firstSequence);

  int get segmentCount => _segments.length;

  static final _uriAttr = RegExp(r'URI="([^"]*)"');

  static final _bandwidth = RegExp(r'[:,]BANDWIDTH=(\d+)');

  /// Si [text] es un playlist maestro, URL de la variante de mayor calidad. `null` si no lo es, o si
  /// el audio va en una pista aparte: habría que recortar las dos a la par, y no se intenta.
  static String? bestVariant(String text, Uri base) {
    final lines = const LineSplitter().convert(text);
    final separateAudio = lines
        .any((l) => l.startsWith('#EXT-X-MEDIA:') && l.contains('TYPE=AUDIO') && l.contains('URI='));
    if (separateAudio) return null;

    String? best;
    var bestRate = -1;
    for (var i = 0; i + 1 < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final uri = lines[i + 1];
      if (uri.isEmpty || uri.startsWith('#')) continue;
      final rate = int.tryParse(_bandwidth.firstMatch(lines[i])?.group(1) ?? '') ?? 0;
      if (rate > bestRate) {
        bestRate = rate;
        best = uri;
      }
    }
    return best == null ? null : base.resolve(best).toString();
  }

  /// Devuelve `null` si no es un playlist al que se le pueda aplicar esto: uno maestro, un directo,
  /// o uno con etiquetas cuyo efecto depende de los segmentos anteriores.
  static HlsPlaylist? parse(String text, Uri base) {
    final lines = const LineSplitter().convert(text);
    if (lines.isEmpty || !lines.first.startsWith('#EXTM3U')) return null;
    if (!lines.any((l) => l.startsWith('#EXT-X-ENDLIST'))) return null;
    if (lines.any((l) => l.startsWith('#EXT-X-STREAM-INF') || l.startsWith('#EXT-X-BYTERANGE'))) {
      return null;
    }

    String resolve(String uri) => base.resolve(uri).toString();
    String resolveTag(String line) =>
        line.replaceAllMapped(_uriAttr, (m) => 'URI="${resolve(m.group(1)!)}"');

    final header = <String>[];
    final segments = <_Segment>[];
    var pending = <String>[];
    var elapsed = Duration.zero;
    var current = Duration.zero;
    var seenExtinf = false;
    var firstSequence = 0;

    for (final line in lines.skip(1)) {
      if (line.isEmpty || line.startsWith('#EXT-X-ENDLIST')) continue;
      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        firstSequence = int.tryParse(line.split(':').last.trim()) ?? 0;
        continue;
      }
      if (line.startsWith('#EXTINF:')) {
        final seconds = double.tryParse(line.substring(8).split(',').first.trim());
        if (seconds == null) return null;
        current = Duration(microseconds: (seconds * 1000000).round());
        seenExtinf = true;
        pending.add(line);
      } else if (line.startsWith('#')) {
        if (!seenExtinf) {
          header.add(resolveTag(line));
        } else {
          // Un MAP o KEY a mitad del playlist afecta a todo lo que le sigue.
          if (line.startsWith('#EXT-X-MAP') || line.startsWith('#EXT-X-KEY')) return null;
          pending.add(line);
        }
      } else {
        if (pending.isEmpty) return null;
        segments.add(_Segment(elapsed, [...pending, resolve(line)]));
        elapsed += current;
        pending = [];
      }
    }
    if (segments.isEmpty || elapsed <= Duration.zero) return null;
    return HlsPlaylist._(header, segments, elapsed, firstSequence);
  }

  /// Manifiesto que empieza en el segmento que contiene [target]. Nunca empieza después de él.
  HlsWindow windowAt(Duration target) {
    var index = 0;
    for (var i = 0; i < _segments.length; i++) {
      if (_segments[i].start > target) break;
      index = i;
    }
    final out = <String>[
      '#EXTM3U',
      ..._header,
      '#EXT-X-MEDIA-SEQUENCE:${_firstSequence + index}',
      for (final s in _segments.skip(index)) ...s.lines,
      '#EXT-X-ENDLIST',
      '',
    ];
    return HlsWindow(offset: _segments[index].start, total: total, manifest: out.join('\n'));
  }
}

/// Sirve un manifiesto a FFmpeg por loopback.
///
/// Se crea uno por apertura: FFmpeg lee un playlist bajo demanda una sola vez, y al suspender la app
/// el sistema puede llevarse el socket.
class LocalManifestServer {
  final HttpServer _server;
  final String url;
  LocalManifestServer._(this._server, this.url);

  static Future<LocalManifestServer> start(String manifest) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final token = Random.secure().nextInt(1 << 32).toRadixString(16);
    final path = '/$token/manifest.m3u8';
    server.listen((req) {
      final res = req.response;
      if (req.uri.path == path) {
        res.headers.set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl');
        res.write(manifest);
      } else {
        res.statusCode = HttpStatus.notFound;
      }
      res.close();
    }, onError: (Object _) {});
    return LocalManifestServer._(server, 'http://127.0.0.1:${server.port}$path');
  }

  Future<void> close() => _server.close(force: true);
}
