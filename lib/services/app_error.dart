import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

enum AppErrorKind { network, serverDown, engine, unknown }

/// Qué le pasó a una carga, en palabras para el usuario.
///
/// Los plugins solo relanzan lo que les da Dio o `Exception('…')`, y algunas pantallas guardan el
/// error como texto: por eso también se clasifica por el mensaje.
class AppError implements Exception {
  final AppErrorKind kind;
  const AppError(this.kind);

  static const engine = AppError(AppErrorKind.engine);

  static final _httpStatus =
      RegExp(r'(status code of|http|código|error)[ :]*(4\d\d|5\d\d)\b', caseSensitive: false);
  static final _networkText = RegExp(
    r'timeout|timed out|socketexception|failed host lookup|handshake|connection (refused|reset|closed|error|abort)'
    r'|network|tcp:|ffurl_read|failed to open|conexi',
    caseSensitive: false,
  );
  static final _serverText =
      RegExp(r'bad gateway|service unavailable|forbidden|not found', caseSensitive: false);

  static AppError from(Object? error) {
    if (error is AppError) return error;
    if (error is DioException) return _fromDio(error);
    if (error is TimeoutException || error is SocketException || error is HandshakeException) {
      return const AppError(AppErrorKind.network);
    }
    return _fromText('${error ?? ''}');
  }

  static AppError _fromDio(DioException e) {
    final host = e.requestOptions.uri.host;
    switch (e.type) {
      case DioExceptionType.badResponse:
        return const AppError(AppErrorKind.serverDown);
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return host == '127.0.0.1' ? engine : const AppError(AppErrorKind.network);
      default:
        return _fromText(e.toString());
    }
  }

  static AppError _fromText(String text) {
    if (text.contains('motor de reproducción')) return engine;
    if (_httpStatus.hasMatch(text) || _serverText.hasMatch(text)) {
      return const AppError(AppErrorKind.serverDown);
    }
    if (_networkText.hasMatch(text)) return const AppError(AppErrorKind.network);
    return const AppError(AppErrorKind.unknown);
  }

  String get message => switch (kind) {
        AppErrorKind.network => 'Parece que hay un problema de conexión. ¿Quieres recargar?',
        AppErrorKind.serverDown =>
          'El servidor de este contenido está caído. Prueba con otro plugin o más tarde.',
        AppErrorKind.engine => 'El motor de reproducción no está activo. Reiniciando...',
        AppErrorKind.unknown =>
          'No pudimos cargar este contenido. Prueba con otro plugin o más tarde.',
      };

  @override
  String toString() => message;
}
