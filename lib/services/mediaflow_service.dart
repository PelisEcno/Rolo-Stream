import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Puente al proxy MediaFlow nativo (Android/iOS).
///
/// El lado nativo debe atender el canal [channelName] con los métodos
/// `startProxy` (devuelve el puerto como int) y `stopProxy`.
class MediaFlowService {
  static const channelName = 'com.rolostream/mediaflow';
  static const MethodChannel _channel = MethodChannel(channelName);

  /// Puerto que se usa si el proxy nativo no arranca o no informa el suyo.
  static const defaultPort = 8888;

  /// Debe coincidir con APP__AUTH__API_PASSWORD del proxy
  /// (ProxyManager.kt en Android, MediaFlowBridge.swift en iOS).
  static const apiPassword = 'changeme';

  static int _port = defaultPort;
  static bool _nativeRunning = false;

  /// Puerto en el que se espera al proxy.
  static int get port => _port;

  /// URL que debe abrir el reproductor. Si el proxy entrega `mediaflow_proxy_url` se usa siempre:
  /// el manifiesto y cada segmento pasan por el proxy, que les pone los headers del extractor
  /// (los CDN que exigen `Referer` en los segmentos devuelven 403 si FFmpeg los pide directo).
  static ({String url, bool viaProxy}) playbackUrl({
    required String host,
    required String directUrl,
    String? proxyUrl,
  }) {
    if (proxyUrl == null) return (url: directUrl, viaProxy: false);
    if (host != 'zilla') return (url: proxyUrl, viaProxy: true);

    // Headers que solo necesita Zilla: a otro host le pisarían el `Referer` del extractor.
    final destUrl = Uri.parse(proxyUrl).queryParameters['d'] ?? 'https://player.zilla-networks.com/';
    return (
      url: '$proxyUrl'
          '&h_referer=${Uri.encodeComponent(destUrl)}'
          '&h_sec-fetch-dest=video'
          '&h_sec-fetch-mode=cors'
          '&h_sec-fetch-site=same-origin'
          '&h_accept=*%2F*'
          '&h_accept-language=en-US%2Cen%3Bq%3D0.9%2Ces%3Bq%3D0.8',
      viaProxy: true,
    );
  }

  /// true solo si el proxy nativo respondió a `startProxy`.
  static bool get nativeRunning => _nativeRunning;

  /// URL base del proxy, p. ej. http://127.0.0.1:8888
  static String get proxyUrl => 'http://127.0.0.1:$_port';

  /// Inicia el proxy nativo y devuelve el puerto en el que escucha.
  /// Si falla, devuelve [defaultPort] (por si el proxy corre por fuera de la app).
  static Future<int> start() async {
    try {
      final int? port = await _channel
          .invokeMethod<int>('startProxy')
          .timeout(const Duration(seconds: 5));
      _port = port ?? defaultPort;
      _nativeRunning = port != null;
    } catch (e) {
      debugPrint('MediaFlow no arrancó ($e). Se usa el puerto $defaultPort.');
      _port = defaultPort;
      _nativeRunning = false;
    }
    return _port;
  }

  static Future<bool>? _ensuring;

  /// Comprueba el puerto. Solo se cambia en las pruebas.
  @visibleForTesting
  static Future<bool> Function() probe = _probePort;

  /// true si algo escucha en el puerto del proxy.
  static Future<bool> isRunning() => probe();

  static Future<bool> _probePort() async {
    try {
      final sock = await Socket.connect('127.0.0.1', _port,
          timeout: const Duration(milliseconds: 600));
      sock.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Comprueba que el proxy responda y, si no, lo reinicia.
  /// Útil al volver de segundo plano, donde el sistema suele matarlo.
  /// Varias llamadas simultáneas comparten el mismo intento.
  static Future<bool> ensureRunning() => _ensuring ??= _ensureRunning().whenComplete(() {
        _ensuring = null;
      });

  static Future<bool> _ensureRunning() async {
    if (await isRunning()) return true;
    debugPrint('MediaFlow no responde, reiniciando…');
    await restart();
    // El arranque es asíncrono: esperamos a que abra el puerto.
    for (var i = 0; i < 15; i++) {
      if (await isRunning()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  /// Reinicia el proxy aunque el lado nativo crea que sigue vivo.
  ///
  /// Con el puerto sin responder, `startProxy` no sirve: al suspender la app iOS se lleva el
  /// socket, pero el flag del servidor sigue en `true` y solo contesta "ya estaba corriendo".
  static Future<void> restart() async {
    try {
      final int? port = await _channel
          .invokeMethod<int>('restartProxy')
          .timeout(const Duration(seconds: 5));
      _port = port ?? defaultPort;
      _nativeRunning = port != null;
    } catch (e) {
      debugPrint('MediaFlow no se reinició ($e).');
      _nativeRunning = false;
    }
  }

  /// Detiene el proxy nativo.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopProxy');
    } catch (e) {
      debugPrint('Error al detener MediaFlow: $e');
    } finally {
      _nativeRunning = false;
    }
  }

  /// URL del extractor para [host] y el embed [embedUrl], con `api_password`.
  /// `d` se codifica porque la URL del embed trae sus propios `?` y `&`.
  static String buildUrl(String host, String embedUrl) {
    return Uri.parse(proxyUrl).replace(
      path: '/extractor/video',
      queryParameters: {
        'host': host,
        'd': embedUrl,
        'api_password': apiPassword,
      },
    ).toString();
  }
}
