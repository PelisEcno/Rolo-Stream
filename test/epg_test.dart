import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:rolostream/iptv/epg.dart';
import 'package:rolostream/iptv/iptv_models.dart';
import 'package:rolostream/iptv/iptv_service.dart';
import 'package:rolostream/iptv/m3u_parser.dart';
import 'package:rolostream/ui/screens/iptv_channel_list_screen.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:rolostream/ui/widgets/premium_player.dart';
import 'package:shared_preferences/shared_preferences.dart';

DateTime t(int h, [int m = 0]) => DateTime.utc(2026, 11, 2, h, m);

void main() {
  group('EPGProgram', () {
    final p = EPGProgram(titulo: 'Partido', inicio: t(20), fin: t(22));

    test('duración y rango horario', () {
      expect(p.duracion, const Duration(hours: 2));
      expect(p.rango, '${EPGProgram.hora(t(20))} - ${EPGProgram.hora(t(22))}');
    });

    test('isLiveAt incluye el inicio y excluye el fin', () {
      expect(p.isLiveAt(t(19, 59)), isFalse);
      expect(p.isLiveAt(t(20)), isTrue);
      expect(p.isLiveAt(t(21, 59)), isTrue);
      expect(p.isLiveAt(t(22)), isFalse);
    });

    test('progressAt va de 0 a 1 y se queda en los extremos', () {
      expect(p.progressAt(t(19)), 0);
      expect(p.progressAt(t(21)), closeTo(0.5, 1e-9));
      expect(p.progressAt(t(23)), 1);
    });

    test('un programa de duración cero no divide por cero', () {
      expect(EPGProgram(titulo: 'x', inicio: t(1), fin: t(1)).progressAt(t(1)), 0);
    });

    test('fin anterior al inicio no es válido', () {
      expect(() => EPGProgram(titulo: 'x', inicio: t(5), fin: t(4)), throwsA(isA<AssertionError>()));
    });

    test('toJson / fromJson conservan los datos', () {
      final back = EPGProgram.fromJson(
          EPGProgram(titulo: 'Noticias', inicio: t(22), fin: t(23), descripcion: 'Resumen').toJson());
      expect(back.titulo, 'Noticias');
      expect(back.inicio.isAtSameMomentAs(t(22)), isTrue);
      expect(back.fin.isAtSameMomentAs(t(23)), isTrue);
      expect(back.descripcion, 'Resumen');
    });
  });

  group('EPGSchedule', () {
    // Se entrega desordenado a propósito.
    final schedule = EPGSchedule([
      EPGProgram(titulo: 'Noticias', inicio: t(22), fin: t(23)),
      EPGProgram(titulo: 'Partido', inicio: t(20), fin: t(22)),
      EPGProgram(titulo: 'Cine', inicio: t(23), fin: t(25)),
    ]);

    test('ordena por hora de inicio', () {
      expect(schedule.programas.map((p) => p.titulo), ['Partido', 'Noticias', 'Cine']);
    });

    test('nowNext devuelve el programa en emisión y el siguiente', () {
      final nn = schedule.nowNext(t(21));
      expect(nn.ahora?.titulo, 'Partido');
      expect(nn.despues?.titulo, 'Noticias');
    });

    test('entre dos programas con hueco no hay "ahora" pero sí "después"', () {
      final gap = EPGSchedule([
        EPGProgram(titulo: 'A', inicio: t(10), fin: t(11)),
        EPGProgram(titulo: 'B', inicio: t(12), fin: t(13)),
      ]);
      final nn = gap.nowNext(t(11, 30));
      expect(nn.ahora, isNull);
      expect(nn.despues?.titulo, 'B');
    });

    test('al terminar todo la guía queda vacía', () {
      expect(schedule.nowNext(t(23, 30) .add(const Duration(days: 1))).isEmpty, isTrue);
      expect(EPGSchedule(const []).isEmpty, isTrue);
    });
  });

  group('EPGService', () {
    test('solo da datos a canales con tvg-id conocido', () {
      final svc = EPGService();
      final now = DateTime.now();
      svc.setSchedule('dep1', [
        EPGProgram(titulo: 'Partido', inicio: now.subtract(const Duration(hours: 1)), fin: now.add(const Duration(hours: 1))),
        EPGProgram(titulo: 'Noticias', inicio: now.add(const Duration(hours: 1)), fin: now.add(const Duration(hours: 2))),
      ]);
      const con = Channel(nombre: 'Deportes', url: 'http://x/1', tvgId: 'dep1');
      const otro = Channel(nombre: 'Otro', url: 'http://x/2', tvgId: 'nada');
      const sin = Channel(nombre: 'Sin id', url: 'http://x/3');

      final nn = svc.nowNextFor(con)!;
      expect(nn.ahora?.titulo, 'Partido');
      expect(nn.despues?.titulo, 'Noticias');
      expect(svc.nowNextFor(otro), isNull);
      expect(svc.nowNextFor(sin), isNull);
    });

    test('setAll carga muchos canales notificando una sola vez', () {
      final svc = EPGService();
      var n = 0;
      svc.addListener(() => n++);
      svc.setAll({
        'a': [EPGProgram(titulo: 'A', inicio: t(1), fin: t(2))],
        'b': [EPGProgram(titulo: 'B', inicio: t(1), fin: t(2))],
      });
      expect(n, 1);
      expect(svc.scheduleFor(const Channel(nombre: 'x', url: 'u', tvgId: 'b'))?.programas.single.titulo, 'B');
    });

    test('notifica al cambiar la guía', () {
      final svc = EPGService();
      var n = 0;
      svc.addListener(() => n++);
      svc.setSchedule('a', const []);
      svc.clear();
      expect(n, 2);
      expect(svc.hasData, isFalse);
    });
  });

  test('el parser conserva tvg-id', () {
    final ch = parseM3U('#EXTM3U\n#EXTINF:-1 tvg-id="dep1" group-title="D",Deportes\nhttp://x/1\n').single;
    expect(ch.tvgId, 'dep1');
  });

  group('selector de calidad', () {
    test('ignora auto/no, ordena de mayor a menor y etiqueta por altura', () {
      final tracks = Tracks(video: [
        VideoTrack.auto(),
        VideoTrack.no(),
        const VideoTrack('1', null, null, w: 640, h: 360, bitrate: 800000),
        const VideoTrack('2', null, null, w: 1920, h: 1080, bitrate: 5000000),
        const VideoTrack('3', null, null, w: 1280, h: 720, bitrate: 2500000),
      ]);
      final v = QualityButton.variantsOf(tracks);
      expect(v.map((t) => QualityButton.labelOf(t)), ['1080p', '720p', '360p']);
    });

    test('sin altura usa el bitrate como etiqueta', () {
      expect(QualityButton.labelOf(const VideoTrack('9', null, null, bitrate: 2500000)), '2.5 Mbps');
    });
  });

  group('marca de agua', () {
    testWidgets('al 40 %, abajo a la derecha y deja pasar los toques', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: SizedBox.expand(
          child: Stack(children: [
            Positioned.fill(child: GestureDetector(onTap: () => taps++)),
            const PlayerWatermark(),
          ]),
        ),
      ));

      expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 0.4);
      final screen = tester.getRect(find.byType(Stack).first);
      final logo = tester.getRect(find.byType(Image));
      expect(screen.right - logo.right, 12);
      expect(screen.bottom - logo.bottom, 8);
      // No debe llegar a la barra de controles, que empieza 40 px por encima del borde.
      expect(screen.bottom - logo.top, lessThan(40));

      await tester.tapAt(logo.center);
      expect(taps, 1);
    });

    testWidgets('el logo está registrado en los assets', (tester) async {
      final bytes = await tester.runAsync(() => rootBundle.load('assets/images/rolostream_logo.png'));
      expect(bytes!.lengthInBytes, greaterThan(0));
    });
  });

  group('StallRecovery', () {
    late StreamController<bool> buffering;
    late bool isBuffering;
    late int reopens;
    late int giveUps;
    late List<Duration> positions;

    void emit(bool b) {
      isBuffering = b;
      buffering.add(b);
    }

    StallRecovery create({Future<void> Function(Duration)? reopen}) => StallRecovery.withSource(
          buffering: buffering.stream,
          isBuffering: () => isBuffering,
          hasMedia: () => true,
          position: () => const Duration(minutes: 5),
          reopen: reopen ??
              (at) async {
                reopens++;
                positions.add(at);
              },
          onGiveUp: () => giveUps++,
        );

    setUp(() {
      buffering = StreamController<bool>(sync: true);
      isBuffering = false;
      reopens = 0;
      giveUps = 0;
      positions = [];
    });

    testWidgets('un buffering corto no reconecta', (tester) async {
      final r = create();
      emit(true);
      await tester.pump(const Duration(seconds: 11));
      emit(false);
      await tester.pump(const Duration(seconds: 30));
      expect(reopens, 0);
      r.dispose();
    });

    testWidgets('un atasco largo reabre en la posición donde iba', (tester) async {
      final r = create();
      emit(true);
      await tester.pump(const Duration(seconds: 12));
      expect(reopens, 1);
      expect(positions.single, const Duration(minutes: 5));
      expect(r.reconnecting.value, isTrue);
      r.dispose();
    });

    testWidgets('se rinde aunque cada reapertura emita buffering=false', (tester) async {
      // Lo que hace `Player.open` de verdad: false y enseguida true otra vez.
      late StallRecovery r;
      r = create(reopen: (_) async {
        reopens++;
        emit(false);
        emit(true);
      });
      emit(true);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(seconds: 12));
      }
      expect(reopens, 3);
      expect(giveUps, greaterThanOrEqualTo(1));
      expect(r.reconnecting.value, isFalse);
      r.dispose();
    });

    testWidgets('si la reproducción se mantiene sana vuelve a tener todos los intentos', (tester) async {
      final r = create();
      for (var ciclo = 0; ciclo < 5; ciclo++) {
        emit(true);
        await tester.pump(const Duration(seconds: 12));
        emit(false);
        await tester.pump(const Duration(seconds: 6));
        expect(r.reconnecting.value, isFalse);
      }
      expect(reopens, 5);
      expect(giveUps, 0);
      r.dispose();
    });

    testWidgets('cerrar el reproductor durante una reapertura no deja nada vivo', (tester) async {
      final pending = Completer<void>();
      final r = create(reopen: (_) => pending.future);
      emit(true);
      await tester.pump(const Duration(seconds: 12));
      r.dispose();
      pending.complete();
      await tester.pump(const Duration(seconds: 60));
      expect(giveUps, 0);
    });
  });

  group('EPG en la lista de canales', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await IPTVService.instance.load();
      EPGService.instance.clear();
    });
    tearDown(() => EPGService.instance.clear());

    final channels = [
      const Channel(nombre: 'Deportes HD', url: 'http://x/1', tvgId: 'dep1', grupo: 'Deportes'),
      const Channel(nombre: 'Canal sin guía', url: 'http://x/2', grupo: 'Deportes'),
    ];

    Future<void> open(WidgetTester tester) async {
      final p = await IPTVService.instance.add(nombre: 'L', url: 'http://srv/l.m3u');
      IPTVService.instance.seedChannels(p.id, channels);
      await tester.pumpWidget(
          MaterialApp(theme: AppTheme.dark, home: IPTVChannelListScreen(playlist: p)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deportes'));
      await tester.pumpAndSettle();
    }

    testWidgets('la tarjeta muestra Ahora/Después y aparece al llegar los datos', (tester) async {
      await open(tester);
      expect(find.textContaining('Ahora:'), findsNothing);

      final now = DateTime.now();
      EPGService.instance.setSchedule('dep1', [
        EPGProgram(titulo: 'Partido de Fútbol', inicio: now.subtract(const Duration(minutes: 30)), fin: now.add(const Duration(minutes: 60))),
        EPGProgram(titulo: 'Noticias', inicio: now.add(const Duration(minutes: 60)), fin: now.add(const Duration(minutes: 90))),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Ahora: Partido de Fútbol'), findsOneWidget);
      expect(find.text('Después: Noticias'), findsOneWidget);
    });

    testWidgets('la vista Guía explica que no hay datos y luego lista los canales con guía', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Guía de programación'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay guía de programación'), findsOneWidget);

      final now = DateTime.now();
      EPGService.instance.setSchedule('dep1', [
        EPGProgram(titulo: 'Partido de Fútbol', inicio: now.subtract(const Duration(minutes: 30)), fin: now.add(const Duration(minutes: 60))),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Deportes HD'), findsOneWidget);
      expect(find.text('Partido de Fútbol'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Canal sin guía'), findsNothing);
    });
  });
}
