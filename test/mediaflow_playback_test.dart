import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/services/mediaflow_service.dart';

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

  test('si el proxy no entrega la URL se abre directo', () {
    final p = MediaFlowService.playbackUrl(host: 'voe', directUrl: direct);
    expect(p.viaProxy, isFalse);
    expect(p.url, direct);
  });
}
