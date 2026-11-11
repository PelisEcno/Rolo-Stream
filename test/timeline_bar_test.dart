import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/services/exo_engine.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:rolostream/ui/widgets/engine_video.dart';
import 'package:rolostream/ui/widgets/premium_player.dart';

class FakeModel implements PlaybackModel {
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _bufferingEvents = StreamController<bool>.broadcast(sync: true);
  final seeks = <Duration>[];
  final selected = <int>[];
  var plays = 0;
  var pauses = 0;
  Duration now = const Duration(seconds: 100);
  bool isBuffering = false;

  void emit(Duration d) {
    now = d;
    _positions.add(d);
  }

  void emitBuffering(bool b) {
    isBuffering = b;
    _bufferingEvents.add(b);
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Duration get position => now;
  @override
  Duration duration = const Duration(seconds: 1430);
  @override
  final ValueNotifier<bool> playing = ValueNotifier<bool>(true);
  @override
  Stream<bool> get bufferingStream => _bufferingEvents.stream;
  @override
  bool get buffering => isBuffering;
  @override
  double volume = 0.5;
  @override
  final ValueNotifier<List<QualityOption>> qualities = ValueNotifier<List<QualityOption>>(const []);
  @override
  int? activeQuality;
  @override
  void selectQuality(int id) => selected.add(id);
  @override
  final ValueNotifier<double> speed = ValueNotifier<double>(1);
  @override
  void setSpeed(double value) => speed.value = value;
  @override
  final ValueNotifier<List<QualityOption>> audioTracks = ValueNotifier<List<QualityOption>>(const []);
  @override
  int? activeAudioTrack;
  final selectedAudio = <int>[];
  @override
  void selectAudioTrack(int id) => selectedAudio.add(id);
  @override
  void play() {
    plays++;
    playing.value = true;
  }

  @override
  void pause() {
    pauses++;
    playing.value = false;
  }

  @override
  Future<void> seek(Duration position) async {
    seeks.add(position);
    now = position;
  }
}

void main() {
  late FakeModel model;
  final phase = ValueNotifier<PlaybackPhase>(PlaybackPhase.playing);

  setUp(() {
    model = FakeModel();
    phase.value = PlaybackPhase.playing;
  });

  group('ExoPlayer: formato del stream', () {
    test('HLS por extensión o por la ruta del proxy', () {
      expect(exoFormatFor('https://cdn/x/master.m3u8?t=1'), 'hls');
      expect(exoFormatFor('http://127.0.0.1:8888/proxy/hls/manifest.m3u8?d=x'), 'hls');
    });

    test('DASH y archivos normales', () {
      expect(exoFormatFor('https://cdn/x/stream.mpd'), 'dash');
      expect(exoFormatFor('http://127.0.0.1:8888/proxy/stream?d=https%3A%2F%2Fa%2Fv.mp4'), isNull);
      expect(exoFormatFor('https://cdn/video.mp4'), isNull);
    });

    test('la URL de destino dentro de la consulta no confunde la detección', () {
      expect(exoFormatFor('http://127.0.0.1:8888/proxy/stream?d=https%3A%2F%2Fa%2Fmaster.m3u8'), isNull);
    });
  });

  group('TimelineBar', () {
    Widget bar() => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 56,
              child: TimelineBar(
                position: model.positionStream,
                currentPosition: () => model.position,
                duration: () => model.duration,
                onSeek: model.seek,
              ),
            ),
          ),
        );
    double value(WidgetTester t) => t.widget<Slider>(find.byType(Slider)).value;

    test('formato de tiempo', () {
      expect(TimelineBar.format(const Duration(seconds: 526)), '08:46');
      expect(TimelineBar.format(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(TimelineBar.format(Duration.zero), '00:00');
    });

    testWidgets('el indicador sigue la posición', (tester) async {
      await tester.pumpWidget(bar());
      expect(find.text('01:40 / 23:50'), findsOneWidget);
      model.emit(const Duration(seconds: 526));
      await tester.pump();
      expect(find.text('08:46 / 23:50'), findsOneWidget);
      expect(value(tester), 526000);
    });

    testWidgets('sin duración conocida no rompe', (tester) async {
      model.duration = Duration.zero;
      model.now = Duration.zero;
      await tester.pumpWidget(bar());
      expect(tester.takeException(), isNull);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('soltar la barra pide el punto elegido', (tester) async {
      await tester.pumpWidget(bar());
      await tester.dragFrom(tester.getCenter(find.byType(Slider)), const Offset(50, 0));
      await tester.pump();
      expect(model.seeks.length, 1);
      expect(model.seeks.single.inSeconds, greaterThan(100));
    });

    testWidgets('mientras se arrastra no salta con la posición que llega', (tester) async {
      await tester.pumpWidget(bar());
      final gesture = await tester.startGesture(tester.getCenter(find.byType(Slider)));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final dragged = value(tester);
      model.emit(const Duration(seconds: 3));
      await tester.pump();
      expect(value(tester), dragged);
      await gesture.up();
      await tester.pump();
      expect(model.seeks, isNotEmpty);
    });

    testWidgets('una posición mayor que el total no rompe', (tester) async {
      await tester.pumpWidget(bar());
      model.emit(const Duration(hours: 5));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(value(tester), 1430000);
    });
  });

  group('EngineVideoView', () {
    var nexts = 0;
    Widget view({bool withNext = false}) => MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 390,
                height: 220,
                child: EngineVideoView(
                  model: model,
                  surface: const SizedBox.expand(),
                  phase: phase,
                  connectingLabel: 'Conectando al servidor...',
                  title: 'Dragon Ball Super · E2',
                  onNext: withNext ? () => nexts++ : null,
                ),
              ),
            ),
          ),
        );

    Offset at(WidgetTester t, double dx, double dy) =>
        t.getTopLeft(find.byType(EngineVideoView)) + Offset(dx, dy);

    Future<void> doubleTap(WidgetTester t, Offset where) async {
      await t.tapAt(where);
      await t.pump(const Duration(milliseconds: 50));
      await t.tapAt(where);
      await t.pumpAndSettle(const Duration(milliseconds: 50));
    }

    /// Deja pasar los temporizadores de ocultar controles y de los avisos.
    Future<void> finish(WidgetTester t) => t.pump(const Duration(seconds: 6));

    testWidgets('lleva la marca de agua y empieza con controles visibles', (tester) async {
      await tester.pumpWidget(view());
      expect(find.text('ROLOSTREAM'), findsOneWidget);
      expect(find.byTooltip('Pausar'), findsOneWidget);
      expect(find.byTooltip('Pantalla completa'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets('pausa y reanuda desde el botón central', (tester) async {
      await tester.pumpWidget(view());
      await tester.tap(find.byTooltip('Pausar'));
      await tester.pump();
      expect(model.pauses, 1);
      await tester.tap(find.byTooltip('Reproducir'));
      await tester.pump();
      expect(model.plays, 1);
      await finish(tester);
    });

    testWidgets('los controles se ocultan a los 5 s y vuelven al tocar', (tester) async {
      await tester.pumpWidget(view());
      double opacity() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).opacity;
      expect(opacity(), 1);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(opacity(), 0);

      await tester.tapAt(at(tester, 195, 60));
      // Sin esperar al posible segundo toque: la animación ya arrancó en el mismo fotograma.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(opacity(), 1);
      await finish(tester);
    });

    testWidgets('con los controles ocultos, sus botones no reciben toques', (tester) async {
      await tester.pumpWidget(view());
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.byType(EngineVideoView)));
      await tester.pump(const Duration(milliseconds: 10));
      expect(model.pauses, 0);
      await finish(tester);
    });

    testWidgets('doble toque a la derecha adelanta y a la izquierda retrocede', (tester) async {
      await tester.pumpWidget(view());
      await doubleTap(tester, at(tester, 370, 40));
      expect(model.seeks.single, const Duration(seconds: 110));

      model.seeks.clear();
      await doubleTap(tester, at(tester, 20, 40));
      expect(model.seeks.single, const Duration(seconds: 100));
      await finish(tester);
    });

    testWidgets('el doble toque no pasa del inicio ni del final', (tester) async {
      model.now = const Duration(seconds: 3);
      await tester.pumpWidget(view());
      await doubleTap(tester, at(tester, 20, 40));
      expect(model.seeks.single, Duration.zero);

      model.seeks.clear();
      model.now = const Duration(seconds: 1425);
      await doubleTap(tester, at(tester, 370, 40));
      expect(model.seeks.single, const Duration(seconds: 1430));
      await finish(tester);
    });

    testWidgets('doble toque en el centro no salta', (tester) async {
      await tester.pumpWidget(view());
      await doubleTap(tester, at(tester, 195, 30));
      expect(model.seeks, isEmpty);
      await finish(tester);
    });

    testWidgets('deslizar a la derecha cambia el volumen', (tester) async {
      await tester.pumpWidget(view());
      await tester.dragFrom(at(tester, 350, 150), const Offset(0, -50));
      await tester.pump();
      expect(model.volume, greaterThan(0.5));
      expect(find.textContaining('Volumen'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('el spinner sale al cargar, con el texto de conexión', (tester) async {
      phase.value = PlaybackPhase.connecting;
      await tester.pumpWidget(view());
      expect(find.text('Conectando al servidor...'), findsOneWidget);

      phase.value = PlaybackPhase.playing;
      await tester.pump();
      expect(find.text('Conectando al servidor...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      model.emitBuffering(true);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await finish(tester);
    });

    testWidgets('el spinner no se queda girando si la carga termina mientras conecta',
        (tester) async {
      // Lo que pasa de verdad: los controles se crean cargando...
      phase.value = PlaybackPhase.connecting;
      model.isBuffering = true;
      await tester.pumpWidget(view());

      // ...la carga termina antes de pasar a reproducir...
      model.emitBuffering(false);
      await tester.pump();

      // ...y al reproducir no debe quedar nada encima del video.
      phase.value = PlaybackPhase.playing;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await finish(tester);
    });

    testWidgets('los botones de ±10 s saltan desde la posición actual', (tester) async {
      await tester.pumpWidget(view());
      await tester.tap(find.byTooltip('Adelantar 10 segundos'));
      await tester.pump();
      expect(model.seeks.last, const Duration(seconds: 110));
      await tester.tap(find.byTooltip('Retroceder 10 segundos'));
      await tester.pump();
      expect(model.seeks.last, const Duration(seconds: 100));
      await finish(tester);
    });

    testWidgets('la velocidad se elige en una hoja y queda marcada', (tester) async {
      await tester.pumpWidget(view());
      await tester.tap(find.byTooltip('Velocidad'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('1.5x'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(model.speed.value, 1.5);
      await finish(tester);
    });

    testWidgets('siguiente episodio solo aparece si hay uno', (tester) async {
      await tester.pumpWidget(view());
      expect(find.byTooltip('Siguiente episodio'), findsNothing);

      nexts = 0;
      await tester.pumpWidget(view(withNext: true));
      await tester.tap(find.byTooltip('Siguiente episodio'));
      await tester.pump();
      expect(nexts, 1);
      await finish(tester);
    });

    testWidgets('el audio solo aparece con más de una pista', (tester) async {
      await tester.pumpWidget(view());
      expect(find.byTooltip('Audio'), findsNothing);

      model.audioTracks.value = const [QualityOption(0, 'Japonés'), QualityOption(1, 'Español')];
      await tester.pump();
      await tester.tap(find.byTooltip('Audio'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('Español'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(model.selectedAudio, [1]);
      await finish(tester);
    });

    testWidgets('el botón de calidad solo aparece con varias y deja elegir', (tester) async {
      await tester.pumpWidget(view());
      expect(find.byTooltip('Calidad'), findsNothing);

      model.qualities.value = const [QualityOption(0, '1080p'), QualityOption(1, '480p')];
      await tester.pump();
      await tester.tap(find.byTooltip('Calidad'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      await tester.tap(find.text('480p'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(model.selected, [1]);
      await finish(tester);
    });

    testWidgets('pantalla completa abre otra vista y al salir vuelve', (tester) async {
      // Cambiar la orientación es una llamada a la plataforma: solo termina con tiempo real.
      Future<void> settle() async {
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      await tester.pumpWidget(view());
      await tester.tap(find.byTooltip('Pantalla completa'));
      await settle();
      expect(find.byTooltip('Salir de pantalla completa'), findsOneWidget);
      expect(find.text('ROLOSTREAM'), findsWidgets);
      expect(find.text('Dragon Ball Super · E2'), findsOneWidget);
      expect(find.text('Velocidad (1x)'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Salir de pantalla completa'));
      await settle();
      expect(find.byTooltip('Salir de pantalla completa'), findsNothing);
      expect(find.byTooltip('Pantalla completa'), findsOneWidget);
      await finish(tester);
    });
  });
}
