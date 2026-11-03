import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    Widget view() => MaterialApp(
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
      await tester.pump(const Duration(milliseconds: 350)); // espera por si es doble toque
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
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Salir de pantalla completa'));
      await settle();
      expect(find.byTooltip('Salir de pantalla completa'), findsNothing);
      expect(find.byTooltip('Pantalla completa'), findsOneWidget);
      await finish(tester);
    });
  });
}
