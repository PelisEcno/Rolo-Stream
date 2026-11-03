import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/ui/screens/fvp_test_screen.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:rolostream/ui/widgets/anime_card.dart';

/// Estas pruebas pintan las tarjetas de verdad: un fallo al pintar deja la imagen en negro sin
/// que nada más se entere.
void main() {
  Widget app(Widget child) => MaterialApp(theme: AppTheme.dark, home: Scaffold(body: child));

  /// Toda la imagen debe cubrir su tarjeta, sin huecos, en cualquier punto del scroll.
  void expectPostersCoverCards(WidgetTester tester, Finder cards) {
    expect(cards, findsWidgets);
    for (final card in cards.evaluate()) {
      final poster = find.descendant(
          of: find.byWidget(card.widget), matching: find.byType(PosterImage));
      final frame = tester.getRect(find.byWidget(card.widget));
      final image = tester.getRect(poster);
      expect(image.left, lessThanOrEqualTo(frame.left + 0.01));
      expect(image.top, lessThanOrEqualTo(frame.top + 0.01));
      expect(image.right, greaterThanOrEqualTo(frame.right - 0.01));
      expect(image.bottom, greaterThanOrEqualTo(frame.bottom - 0.01));
    }
  }

  testWidgets('AnimeCard en una cuadrícula se pinta con la imagen cubriendo la tarjeta', (tester) async {
    await tester.pumpWidget(app(AnimeGrid(
      count: 30,
      builder: (i) => AnimeCard(nombre: 'Serie $i', imagen: '', onTap: () {}),
    )));
    expect(tester.takeException(), isNull);
    expectPostersCoverCards(tester, find.byType(AnimeCard));
    expect(find.text('Serie 0'), findsOneWidget);

    await tester.drag(find.byType(GridView), const Offset(0, -300));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expectPostersCoverCards(tester, find.byType(AnimeCard));
  });

  testWidgets('el paralaje mueve la imagen al hacer scroll, más despacio que la tarjeta', (tester) async {
    await tester.pumpWidget(app(AnimeGrid(
      count: 30,
      builder: (i) => AnimeCard(nombre: 'Serie $i', imagen: '', onTap: () {}),
    )));
    final card = find.widgetWithText(AnimeCard, 'Serie 8');
    final poster = find.descendant(of: card, matching: find.byType(PosterImage));
    double offsetInside() => tester.getRect(poster).top - tester.getRect(card).top;

    final before = offsetInside();
    await tester.drag(find.byType(GridView), const Offset(0, -120));
    await tester.pump();
    expect(offsetInside(), isNot(closeTo(before, 0.01)));
  });

  testWidgets('en un carrusel horizontal también se pinta', (tester) async {
    await tester.pumpWidget(app(SectionRow(
      title: 'Fila',
      count: 12,
      builder: (i) => CatalogCard(nombre: 'Peli $i', imagen: '', tipo: 'TV', anio: '2026', onTap: () {}),
    )));
    expect(tester.takeException(), isNull);
    expectPostersCoverCards(tester, find.byType(CatalogCard));

    await tester.drag(find.byType(ListView), const Offset(-200, 0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expectPostersCoverCards(tester, find.byType(CatalogCard));
  });

  testWidgets('fuera de un scroll usa la imagen sin paralaje', (tester) async {
    await tester.pumpWidget(app(Center(
      child: SizedBox(
        width: 120,
        height: 180,
        child: AnimeCard(nombre: 'Sola', imagen: '', onTap: () {}),
      ),
    )));
    expect(tester.takeException(), isNull);
    expect(find.byType(Flow), findsNothing);
    expect(find.byType(PosterImage), findsOneWidget);
  });

  group('SeekProbe', () {
    final t0 = DateTime(2026, 11, 3, 12);
    const target = Duration(seconds: 526);
    DateTime at(int s) => t0.add(Duration(seconds: s));

    test('es OK solo si el video avanza tras llegar', () {
      final p = SeekProbe(target, t0);
      expect(p.update(const Duration(seconds: 10), at(1)), isNull);
      expect(p.update(const Duration(seconds: 520), at(2)), isNull);
      expect(p.update(const Duration(seconds: 520), at(3)), isNull);
      expect(p.update(const Duration(seconds: 522), at(4)), startsWith('OK'));
    });

    test('llegar y quedarse quieto es CLAVADO, aunque la posición sea la correcta', () {
      final p = SeekProbe(target, t0);
      for (var s = 1; s < 15; s++) {
        expect(p.update(target, at(s)), isNull);
      }
      expect(p.update(target, at(15)), startsWith('CLAVADO'));
    });

    test('no llegar nunca es CLAVADO', () {
      final p = SeekProbe(target, t0);
      expect(p.update(const Duration(seconds: 5), at(16)), startsWith('CLAVADO'));
    });

    test('seguir avanzando desde antes del salto no cuenta como llegar', () {
      final p = SeekProbe(target, t0);
      expect(p.update(const Duration(seconds: 100), at(1)), isNull);
      expect(p.update(const Duration(seconds: 102), at(3)), isNull);
    });
  });

  testWidgets('tocar la tarjeta llama a onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(app(AnimeGrid(
      count: 3,
      builder: (i) => AnimeCard(nombre: 'Serie $i', imagen: '', onTap: () => taps++),
    )));
    await tester.tap(find.text('Serie 1'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
