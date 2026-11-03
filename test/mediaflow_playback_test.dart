import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/services/mediaflow_service.dart';
import 'package:rolostream/ui/widgets/debug_console.dart';

void main() {
  const direct = 'https://cdn.example/master.m3u8';
  const proxy = 'http://127.0.0.1:8888/proxy/hls/manifest.m3u8'
      '?d=https%3A%2F%2Fcdn.example%2Fmaster.m3u8&api_password=x&h_referer=https%3A%2F%2Fvoe.sx%2Fe%2Fabc';

  test('Voe abre la URL del proxy tal cual, con el Referer del extractor', () {
    final p = MediaFlowService.playbackUrl(host: 'voe', directUrl: direct, proxyUrl: proxy);
    expect(p.viaProxy, isTrue);
    expect(p.url, proxy);
    expect(Uri.parse(p.url).queryParametersAll['h_referer'], ['https://voe.sx/e/abc']);
  });

  test('cualquier otro host también va por el proxy, sin los headers de Zilla', () {
    for (final host in ['mp4upload', 'streamwish', 'doodstream', 'yourupload']) {
      final p = MediaFlowService.playbackUrl(host: host, directUrl: direct, proxyUrl: proxy);
      expect(p.viaProxy, isTrue, reason: host);
      expect(p.url, proxy, reason: host);
    }
  });

  test('Zilla conserva sus headers propios', () {
    final p = MediaFlowService.playbackUrl(host: 'zilla', directUrl: direct, proxyUrl: proxy);
    expect(p.viaProxy, isTrue);
    expect(p.url, startsWith(proxy));
    expect(p.url, contains('h_sec-fetch-dest=video'));
  });

  test('ningún host fija Range: el proxy pisaría el que pide FFmpeg y leería bytes equivocados', () {
    for (final host in ['zilla', 'voe', 'mp4upload']) {
      final p = MediaFlowService.playbackUrl(host: host, directUrl: direct, proxyUrl: proxy);
      expect(Uri.parse(p.url).queryParameters.keys.map((k) => k.toLowerCase()),
          isNot(contains('h_range')),
          reason: host);
    }
  });

  test('solo se agrupan los errores del parser AV1, no otros del reproductor', () {
    for (final noise in [
      'NULL: obu_forbidden_bit out of range: 1, but must be in [0,0].',
      'NULL: Failed to parse temporal unit.',
      'NULL: Invalid OBU length: 4427, but only 3 bytes remaining in fragment.',
      'NULL: seq_profile out of range: 4, but must be in [0,2].',
      'NULL: Failed to read unit 0 (type 1).',
    ]) {
      expect(DebugLog.isAv1ParserNoise(noise), isTrue, reason: noise);
    }
    expect(DebugLog.isAv1ParserNoise('hls: Error when loading first segment'), isFalse);
    expect(DebugLog.isAv1ParserNoise('tcp: Connection timed out'), isFalse);
  });

  test('si el proxy no entrega la URL se abre directo', () {
    final p = MediaFlowService.playbackUrl(host: 'voe', directUrl: direct);
    expect(p.viaProxy, isFalse);
    expect(p.url, direct);
  });
}
