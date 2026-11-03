import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/services/hls_window.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:rolostream/ui/widgets/premium_player.dart';

HlsWindow windowAt(int seconds) => HlsWindow(
    offset: Duration(seconds: seconds), total: const Duration(seconds: 1430), manifest: '');

void main() {
  late StreamController<Duration> position;
  late ValueNotifier<HlsWindow?> window;
  var now = Duration.zero;
  Duration? sought;

  void emit(Duration d) {
    now = d;
    position.add(d);
  }

  // La barra se construye una sola vez: igual que en pantalla completa, donde los controles se
  // quedan con el tema que había al entrar.
  Widget bar() => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 56,
            child: TimelineBar(
              position: position.stream,
              currentPosition: () => now,
              window: window,
              onSeek: (d) => sought = d,
            ),
          ),
        ),
      );

  double sliderValue(WidgetTester tester) => tester.widget<Slider>(find.byType(Slider)).value;

  setUp(() {
    position = StreamController<Duration>.broadcast(sync: true);
    window = ValueNotifier(windowAt(520));
    now = Duration.zero;
    sought = null;
  });

  test('formato de tiempo', () {
    expect(TimelineBar.format(const Duration(seconds: 526)), '08:46');
    expect(TimelineBar.format(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(TimelineBar.format(Duration.zero), '00:00');
  });

  testWidgets('muestra el tiempo real del episodio, no el del tramo', (tester) async {
    await tester.pumpWidget(bar());
    expect(find.text('08:40 / 23:50'), findsOneWidget);

    emit(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('08:46 / 23:50'), findsOneWidget);
    expect(sliderValue(tester), 526000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('al abrir otro tramo el indicador va al punto nuevo sin reconstruir la barra',
      (tester) async {
    await tester.pumpWidget(bar());
    expect(sliderValue(tester), 520000);

    // El tramo nuevo: la posición del reproductor vuelve a 0.
    now = Duration.zero;
    window.value = windowAt(1200);
    await tester.pump();
    expect(find.text('20:00 / 23:50'), findsOneWidget);
    expect(sliderValue(tester), 1200000);

    emit(const Duration(seconds: 10));
    await tester.pump();
    expect(sliderValue(tester), 1210000);
  });

  testWidgets('el indicador se dibuja donde corresponde', (tester) async {
    await tester.pumpWidget(bar());
    final rect = tester.getRect(find.byType(Slider));

    window.value = windowAt(0);
    await tester.pump();
    expect(sliderValue(tester), 0);

    window.value = windowAt(1400);
    await tester.pump();
    expect(sliderValue(tester) / 1430000, closeTo(1400 / 1430, 0.001));
    expect(rect.width, greaterThan(100), reason: 'la barra debe tener sitio para moverse');
  });

  testWidgets('sin tramo no dibuja nada', (tester) async {
    window.value = null;
    await tester.pumpWidget(bar());
    expect(find.byType(Slider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('soltar la barra pide el tiempo real elegido', (tester) async {
    await tester.pumpWidget(bar());
    final slider = tester.getRect(find.byType(Slider));

    await tester.dragFrom(tester.getCenter(find.byType(Slider)), Offset(slider.width / 4, 0));
    await tester.pump();

    expect(sought, isNotNull);
    expect(sought!.inSeconds, greaterThan(520));
    expect(sought! <= const Duration(seconds: 1430), isTrue);
  });

  testWidgets('mientras se arrastra no salta con la posición que llega', (tester) async {
    await tester.pumpWidget(bar());
    final gesture = await tester.startGesture(tester.getCenter(find.byType(Slider)));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();
    final dragged = sliderValue(tester);

    emit(const Duration(seconds: 3));
    await tester.pump();
    expect(sliderValue(tester), dragged);

    await gesture.up();
    await tester.pump();
    expect(sought, isNotNull);
  });

  testWidgets('una posición mayor que el total no rompe la barra', (tester) async {
    await tester.pumpWidget(bar());
    emit(const Duration(hours: 5));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(sliderValue(tester), 1430000);
  });
}
