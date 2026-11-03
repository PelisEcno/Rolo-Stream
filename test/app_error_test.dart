import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/services/app_error.dart';
import 'package:rolostream/services/mediaflow_service.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:rolostream/ui/widgets/anime_card.dart';

DioException dio(DioExceptionType type, {String url = 'https://sitio.example/x', int? status}) {
  final req = RequestOptions(path: url);
  return DioException(
    requestOptions: req,
    type: type,
    response: status == null ? null : Response(requestOptions: req, statusCode: status),
  );
}

void main() {
  AppErrorKind kind(Object? e) => AppError.from(e).kind;

  group('clasificación', () {
    test('tiempo de espera y falta de red', () {
      expect(kind(dio(DioExceptionType.connectionTimeout)), AppErrorKind.network);
      expect(kind(dio(DioExceptionType.receiveTimeout)), AppErrorKind.network);
      expect(kind(dio(DioExceptionType.connectionError)), AppErrorKind.network);
      expect(kind(TimeoutException('x')), AppErrorKind.network);
      expect(kind(const SocketException('x')), AppErrorKind.network);
    });

    test('servidor caído', () {
      expect(kind(dio(DioExceptionType.badResponse, status: 502)), AppErrorKind.serverDown);
      expect(kind(dio(DioExceptionType.badResponse, status: 404)), AppErrorKind.serverDown);
    });

    test('el proxy local sin responder es el motor, no la red', () {
      expect(kind(dio(DioExceptionType.connectionError, url: 'http://127.0.0.1:8888/extractor/video')),
          AppErrorKind.engine);
      expect(kind(AppError.engine), AppErrorKind.engine);
    });

    test('también desde el texto que guardan algunas pantallas', () {
      expect(kind('DioException [bad response]: status code of 502'), AppErrorKind.serverDown);
      expect(kind('HTTP 404'), AppErrorKind.serverDown);
      expect(kind('DioException [connection timeout]: The request connection took longer'),
          AppErrorKind.network);
      expect(kind('Failed to open http://127.0.0.1:8888/proxy/hls'), AppErrorKind.network);
      expect(kind('Se perdió la conexión con el servidor'), AppErrorKind.network);
      expect(kind(AppError.engine.message), AppErrorKind.engine);
    });

    test('un número cualquiera en una URL no es un código HTTP', () {
      expect(kind('No se encontró el anime "naruto-404"'), AppErrorKind.unknown);
      expect(kind(null), AppErrorKind.unknown);
    });
  });

  test('mensajes pedidos para cada causa', () {
    expect(const AppError(AppErrorKind.network).message,
        'Parece que hay un problema de conexión. ¿Quieres recargar?');
    expect(const AppError(AppErrorKind.serverDown).message,
        'El servidor de este contenido está caído. Prueba con otro plugin o más tarde.');
    expect(AppError.engine.message, 'El motor de reproducción no está activo. Reiniciando...');
  });

  group('ErrorState', () {
    Widget app(Widget child) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child));

    testWidgets('red: ofrece recargar', (tester) async {
      var retries = 0;
      await tester.pumpWidget(app(
          ErrorState(error: dio(DioExceptionType.receiveTimeout), onRetry: () => retries++)));
      expect(find.textContaining('problema de conexión'), findsOneWidget);
      await tester.tap(find.text('RECARGAR'));
      expect(retries, 1);
    });

    testWidgets('motor: se reinicia solo y vuelve a cargar', (tester) async {
      var retries = 0;
      final done = Completer<bool>();
      await tester.pumpWidget(app(ErrorState(
          error: AppError.engine, onRetry: () => retries++, restartEngine: () => done.future)));
      expect(find.text(AppError.engine.message), findsOneWidget);
      expect(find.text('REINTENTAR'), findsNothing);
      done.complete(true);
      await tester.pump();
      expect(retries, 1);
    });

    testWidgets('motor: si no arranca lo dice y deja reintentar', (tester) async {
      await tester.pumpWidget(app(ErrorState(
          error: AppError.engine, onRetry: () {}, restartEngine: () async => false)));
      await tester.pump();
      expect(find.textContaining('No se pudo reiniciar'), findsOneWidget);
      expect(find.text('REINTENTAR'), findsOneWidget);
    });

    testWidgets('un mensaje propio sustituye al de la causa', (tester) async {
      await tester.pumpWidget(app(ErrorState(error: 'x', message: 'Revisa la contraseña', onRetry: () {})));
      expect(find.text('Revisa la contraseña'), findsOneWidget);
    });
  });

  group('watchdog del proxy', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(MediaFlowService.channelName);
    final calls = <String>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return 8888;
      });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('con el puerto activo no toca nada', () async {
      MediaFlowService.probe = () async => true;
      expect(await MediaFlowService.ensureRunning(), isTrue);
      expect(calls, isEmpty);
    });

    test('con el puerto muerto fuerza el reinicio, no un simple start', () async {
      var alive = false;
      MediaFlowService.probe = () async => alive;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        alive = true;
        return 8888;
      });
      expect(await MediaFlowService.ensureRunning(), isTrue);
      expect(calls, ['restartProxy']);
    });

    test('varias comprobaciones a la vez comparten un solo reinicio', () async {
      var alive = false;
      MediaFlowService.probe = () async => alive;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        alive = true;
        return 8888;
      });
      await Future.wait([MediaFlowService.ensureRunning(), MediaFlowService.ensureRunning()]);
      expect(calls, ['restartProxy']);
    });
  });
}
