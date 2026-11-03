import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:rolostream/ui/widgets/premium_player.dart';

void main() {
  late StreamController<Duration> position;
  Duration? sought;

  Widget bar({Duration offset = const Duration(seconds: 520)}) => MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 56,
            child: TimelineBar(
              position: position.stream,
              initialPosition: Duration.zero,
              offset: offset,
              total: const Duration(seconds: 1430),
              onSeek: (d) => sought = d,
            ),
          ),
        ),
      );

  setUp(() {
    position = StreamController<Duration>(sync: true);
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

    position.add(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('08:46 / 23:50'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 526000);
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
    final dragged = tester.widget<Slider>(find.byType(Slider)).value;

    position.add(const Duration(seconds: 3));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, dragged);

    await gesture.up();
    await tester.pump();
    expect(sought, isNotNull);
  });

  testWidgets('una posición mayor que el total no rompe la barra', (tester) async {
    await tester.pumpWidget(bar());
    position.add(const Duration(hours: 5));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 1430000);
  });
}
