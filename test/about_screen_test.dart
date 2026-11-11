import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/ui/screens/about_screen.dart';
import 'package:rolostream/ui/theme/app_theme.dart';

void main() {
  late List<String> opened;

  Future<void> open(WidgetTester tester) async {
    opened = [];
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AboutScreen(openUrl: (url) async => opened.add(url)),
    ));
  }

  testWidgets('muestra quién lo hace y cómo colaborar, sin desbordar en un móvil', (tester) async {
    await open(tester);
    expect(find.text(developerName), findsOneWidget);
    expect(find.text('$studioName · @$githubUser'), findsOneWidget);
    expect(find.textContaining('cualquier persona puede colaborar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cada enlace abre su dirección de GitHub', (tester) async {
    await open(tester);
    for (final (label, url) in [
      ('Mi perfil de GitHub', 'https://github.com/PelisEcno'),
      ('Código de RoloStream', 'https://github.com/PelisEcno/Rolo-Stream'),
      ('Reportar un fallo', 'https://github.com/PelisEcno/Rolo-Stream/issues'),
      ('Crear un plugin', 'https://github.com/PelisEcno/rolostream_core'),
    ]) {
      await tester.scrollUntilVisible(find.text(label), 100);
      await tester.tap(find.text(label));
      expect(opened.last, url, reason: label);
    }
    expect(opened.length, 4);
  });
}
