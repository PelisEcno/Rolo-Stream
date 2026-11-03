import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:rolostream/iptv/epg.dart';
import 'package:rolostream/iptv/iptv_models.dart';
import 'package:rolostream/iptv/iptv_service.dart';
import 'package:rolostream/iptv/m3u_parser.dart';
import 'package:rolostream/ui/screens/iptv_channel_list_screen.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:rolostream/ui/widgets/epg_timeline.dart';
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
    testWidgets('es texto al 30 %, abajo a la derecha, y deja pasar los toques', (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: SizedBox.expand(
          child: Stack(children: [
            Positioned.fill(child: GestureDetector(onTap: () => taps++)),
            const PlayerWatermark(),
          ]),
        ),
      ));

      final text = tester.widget<Text>(find.text('ROLOSTREAM'));
      expect(text.style!.color!.a, closeTo(0.3, 0.01));
      expect(find.byType(Image), findsNothing);

      final screen = tester.getRect(find.byType(Stack).first);
      final rect = tester.getRect(find.text('ROLOSTREAM'));
      expect(screen.right - rect.right, 12);
      expect(screen.bottom - rect.bottom, 4);
      // El icono de pantalla completa empieza 16 px por encima del borde.
      expect(screen.bottom - rect.top, lessThanOrEqualTo(16));

      await tester.tapAt(rect.center);
      expect(taps, 1);
    });
  });

  group('audio en directo', () {
    const a1 = AudioTrack('1', null, null);
    const a2 = AudioTrack('2', null, null);

    test('con auto fija la primera pista real', () {
      final t = Tracks(audio: [AudioTrack.auto(), AudioTrack.no(), a1, a2]);
      expect(liveAudioTrackToForce(t, Track(audio: AudioTrack.auto()))?.id, '1');
    });

    test('respeta una pista ya elegida y no hace nada sin pistas', () {
      final t = Tracks(audio: [AudioTrack.auto(), AudioTrack.no(), a1, a2]);
      expect(liveAudioTrackToForce(t, const Track(audio: a2)), isNull);
      expect(
          liveAudioTrackToForce(Tracks(audio: [AudioTrack.auto(), AudioTrack.no()]),
              Track(audio: AudioTrack.auto())),
          isNull);
    });
  });

  group('línea de tiempo de la guía', () {
    final start = DateTime(2026, 11, 2, 20);
    final end = start.add(const Duration(hours: 6));

    test('la ventana empieza media hora antes de la franja actual', () {
      expect(EpgTimeline.windowStart(DateTime(2026, 11, 2, 20, 45)), DateTime(2026, 11, 2, 20));
      expect(EpgTimeline.windowStart(DateTime(2026, 11, 2, 20, 10)), DateTime(2026, 11, 2, 19, 30));
    });

    test('coloca el programa según su hora y duración', () {
      final b = EpgTimeline.blockFor(
          EPGProgram(titulo: 'x', inicio: start.add(const Duration(minutes: 30)), fin: start.add(const Duration(minutes: 90))),
          start,
          end)!;
      expect(b.left, 30 * EpgTimeline.pxPerMinute);
      expect(b.width, 60 * EpgTimeline.pxPerMinute);
    });

    test('recorta lo que sobresale y descarta lo que queda fuera', () {
      final b = EpgTimeline.blockFor(
          EPGProgram(titulo: 'x', inicio: start.subtract(const Duration(hours: 1)), fin: start.add(const Duration(minutes: 30))),
          start,
          end)!;
      expect(b.left, 0);
      expect(b.width, 30 * EpgTimeline.pxPerMinute);
      expect(
          EpgTimeline.blockFor(EPGProgram(titulo: 'x', inicio: start.subtract(const Duration(hours: 2)), fin: start), start, end),
          isNull);
      expect(EpgTimeline.blockFor(EPGProgram(titulo: 'x', inicio: end, fin: end.add(const Duration(hours: 1))), start, end), isNull);
    });
  });

  group('PlaybackWatchdog', () {
    late StreamController<Duration> position;
    late bool watching;
    late List<Duration> reopens;
    late int giveUps;
    late PlaybackWatchdog dog;

    // El vigilante se crea dentro de la prueba: su suscripción debe usar el reloj simulado.
    void dogTest(String name, Future<void> Function(WidgetTester) body) {
      testWidgets(name, (tester) async {
        position = StreamController<Duration>(sync: true);
        watching = true;
        reopens = [];
        giveUps = 0;
        dog = PlaybackWatchdog.withSource(
          position: position.stream,
          shouldWatch: () => watching,
          reopen: (at) async => reopens.add(at),
          onGiveUp: () => giveUps++,
        );
        await body(tester);
        dog.dispose();
      });
    }

    /// Hace avanzar la reproducción en pasos de medio segundo.
    void play(int fromMs, int toMs) {
      for (var ms = fromMs; ms <= toMs; ms += 500) {
        position.add(Duration(milliseconds: ms));
      }
    }

    dogTest('al arrancar pasa de conectando a reproduciendo sin reabrir', (tester) async {
      dog.begin();
      expect(dog.phase.value, PlaybackPhase.connecting);
      await tester.pump(const Duration(seconds: 9));
      play(0, 1500);
      expect(dog.phase.value, PlaybackPhase.playing);
      await tester.pump(const Duration(seconds: 2));
      expect(reopens, isEmpty);
    });

    dogTest('a los 10 s sin arrancar reabre y dice que reintenta', (tester) async {
      dog.begin();
      await tester.pump(const Duration(milliseconds: 9999));
      expect(reopens, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(reopens, [Duration.zero]);
      expect(dog.phase.value, PlaybackPhase.retrying);
    });

    dogTest('cada intento espera más: un stream lento llega a arrancar', (tester) async {
      dog.begin();
      await tester.pump(const Duration(seconds: 10));
      expect(reopens.length, 1);
      await tester.pump(const Duration(seconds: 14));
      expect(reopens.length, 1); // el segundo intento aguanta 15 s
      play(0, 1500);
      expect(dog.phase.value, PlaybackPhase.playing);
    });

    dogTest('agotados los intentos se rinde una sola vez y deja de reabrir', (tester) async {
      dog.begin();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 15));
      expect(reopens.length, 2);
      await tester.pump(const Duration(seconds: 20));
      expect(giveUps, 1);
      expect(dog.phase.value, PlaybackPhase.failed);
      await tester.pump(const Duration(seconds: 120));
      expect(reopens.length, 2);
      expect(giveUps, 1);
    });

    dogTest('el salto de posición de un seek o de open no cuenta como arrancar', (tester) async {
      dog.begin();
      position.add(Duration.zero);
      position.add(const Duration(minutes: 5));
      position.add(Duration.zero);
      expect(dog.phase.value, PlaybackPhase.connecting);
      await tester.pump(const Duration(seconds: 10));
      expect(reopens.length, 1);
    });

    dogTest('un atasco en plena reproducción reabre donde iba', (tester) async {
      dog.begin();
      play(60000, 62000);
      expect(dog.phase.value, PlaybackPhase.playing);
      await tester.pump(const Duration(seconds: 11));
      expect(reopens, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(reopens, [const Duration(seconds: 62)]);
      expect(dog.phase.value, PlaybackPhase.retrying);

      // `open` devuelve la posición a 0: un segundo reintento no debe perder el punto.
      position.add(Duration.zero);
      await tester.pump(const Duration(seconds: 15));
      expect(reopens.last, const Duration(seconds: 62));
    });

    dogTest('al recuperarse vuelve a tener todos los intentos', (tester) async {
      dog.begin();
      for (var ciclo = 0; ciclo < 5; ciclo++) {
        final base = ciclo * 100000;
        play(base, base + 2000);
        expect(dog.phase.value, PlaybackPhase.playing);
        await tester.pump(const Duration(seconds: 12));
      }
      expect(reopens.length, 5);
      expect(giveUps, 0);
    });

    dogTest('una pausa o el final del video no se toman por un atasco', (tester) async {
      dog.begin();
      play(0, 2000);
      watching = false;
      await tester.pump(const Duration(seconds: 120));
      expect(reopens, isEmpty);
      expect(dog.phase.value, PlaybackPhase.playing);
    });

    dogTest('stop cancela la vigilancia', (tester) async {
      dog.begin();
      dog.stop();
      await tester.pump(const Duration(seconds: 120));
      expect(reopens, isEmpty);
      expect(dog.phase.value, PlaybackPhase.idle);
    });

    dogTest('connecting no reabre mientras se resuelve el servidor', (tester) async {
      dog.begin();
      dog.connecting();
      await tester.pump(const Duration(seconds: 120));
      expect(reopens, isEmpty);
      expect(dog.phase.value, PlaybackPhase.connecting);
    });
  });

  group('decodificación', () {
    test('solo iOS fuerza software', () {
      expect(hwdecFor(TargetPlatform.iOS), 'no');
      expect(hwdecFor(TargetPlatform.android), isNull);
    });
  });

  group('directo o bajo demanda', () {
    bool? isLive(String url) => Channel(nombre: 'x', url: url).isLive;

    test('Xtream Codes', () {
      expect(isLive('http://srv:8080/user/pass/123'), isTrue);
      expect(isLive('http://srv:8080/user/pass/123.ts'), isTrue);
      expect(isLive('http://srv:8080/live/user/pass/123.m3u8'), isTrue);
      expect(isLive('http://srv:8080/movie/user/pass/123.mkv'), isFalse);
      expect(isLive('http://srv:8080/series/user/pass/123.mp4'), isFalse);
      expect(isLive('http://srv:8080/movie/user/pass/123'), isFalse);
    });

    test('otras listas: por extensión, y un m3u8 cualquiera queda sin decidir', () {
      expect(isLive('https://cdn/peli.MP4'), isFalse);
      expect(isLive('https://cdn/canal/index.m3u8'), isNull);
    });
  });

  group('controles', () {
    MaterialVideoControlsThemeData theme(MaterialVideoControlsThemeData base, {required bool live}) =>
        premiumControlsTheme(base,
            live: live, quality: const SizedBox(), livePlayButton: const Text('live'));

    bool has<T>(List<Widget> bar) => bar.any((w) => w is T);

    for (final base in [
      kDefaultMaterialVideoControlsThemeData,
      kDefaultMaterialVideoControlsThemeDataFullscreen,
    ]) {
      test('en directo no hay barra, ni pausa, ni nada para buscar', () {
        final t = theme(base, live: true);
        expect(t.displaySeekBar, isFalse);
        expect(t.seekGesture, isFalse);
        expect(t.seekOnDoubleTap, isFalse);
        expect(t.seekOnDoubleTapEnabledWhileControlsVisible, isFalse);
        expect(has<MaterialPlayOrPauseButton>(t.primaryButtonBar), isFalse);
        expect(has<MaterialPositionIndicator>(t.bottomButtonBar), isFalse);
        expect(has<MaterialFullscreenButton>(t.bottomButtonBar), isTrue);
      });

      test('bajo demanda conserva barra, pausa y búsqueda', () {
        final t = theme(base, live: false);
        expect(t.displaySeekBar, isTrue);
        expect(t.seekGesture, isTrue);
        expect(t.seekOnDoubleTap, isTrue);
        expect(has<MaterialPlayOrPauseButton>(t.primaryButtonBar), isTrue);
        expect(has<MaterialPositionIndicator>(t.bottomButtonBar), isTrue);
      });

      test('los controles se ven al entrar y duran 5 s', () {
        final t = theme(base, live: true);
        expect(t.visibleOnMount, isTrue);
        expect(t.controlsHoverDuration, const Duration(seconds: 5));
      });
    }

    test('no se añaden márgenes que dejen sin toques la parte baja del video', () {
      final t = theme(kDefaultMaterialVideoControlsThemeData, live: false);
      final deadZone = 16 + t.bottomButtonBarMargin.vertical + t.buttonBarHeight;
      expect(deadZone, 72); // sobre unos 210 px de alto
    });

    testWidgets('el botón de directo solo permite reproducir, nunca pausar', (tester) async {
      final playing = StreamController<bool>(sync: true);
      var plays = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LivePlayButton(
            playing: playing.stream,
            initialPlaying: true,
            onPlay: () => plays++,
          ),
        ),
      ));
      expect(find.byType(IconButton), findsNothing);

      playing.add(false);
      await tester.pump();
      await tester.tap(find.byType(IconButton));
      expect(plays, 1);

      playing.add(true);
      await tester.pump();
      expect(find.byType(IconButton), findsNothing);
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
      expect(find.byType(FractionallySizedBox), findsOneWidget); // lo ya emitido
      expect(find.text('Canal sin guía'), findsNothing);
    });
  });
}
