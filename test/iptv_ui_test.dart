import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/iptv/iptv_models.dart';
import 'package:rolostream/iptv/iptv_service.dart';
import 'package:rolostream/ui/screens/iptv_channel_list_screen.dart';
import 'package:rolostream/ui/screens/iptv_manager_screen.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget app(Widget home) => MaterialApp(theme: AppTheme.dark, home: home);

const xtreamUrl = 'http://srv.example:8080/get.php?username=USUARIO&password=SECRETO&type=m3u_plus';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final svc = IPTVService.instance;
    await svc.load();
    for (final p in svc.playlists) {
      await svc.remove(p.id);
    }
  });

  group('IPTVManagerScreen', () {
    testWidgets('sin listas muestra el estado vacío', (tester) async {
      await tester.pumpWidget(app(const IPTVManagerScreen()));
      expect(find.text('Aún no tienes listas'), findsOneWidget);
      expect(find.text('AÑADIR LISTA'), findsOneWidget);
    });

    testWidgets('rechaza una URL inválida y acepta una válida', (tester) async {
      await tester.pumpWidget(app(const IPTVManagerScreen()));
      await tester.tap(find.text('AÑADIR LISTA'));
      await tester.pumpAndSettle();
      expect(find.text('Añadir lista'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'URL de la lista'), 'no-es-una-url');
      await tester.tap(find.text('AÑADIR'));
      await tester.pump();
      expect(find.text('Escribe una URL que empiece por http:// o https://'), findsOneWidget);
      expect(IPTVService.instance.playlists, isEmpty);

      await tester.enterText(find.widgetWithText(TextFormField, 'Nombre (opcional)'), 'Mi lista');
      await tester.enterText(find.widgetWithText(TextFormField, 'URL de la lista'), xtreamUrl);
      await tester.tap(find.text('AÑADIR'));
      await tester.pumpAndSettle();

      expect(IPTVService.instance.playlists.single.nombre, 'Mi lista');
      expect(IPTVService.instance.playlists.single.tipo, IPTVType.xtream);
      expect(find.text('Mi lista'), findsOneWidget);
      // Se muestra el servidor, nunca el usuario ni la contraseña.
      expect(find.text('Xtream Codes · srv.example'), findsOneWidget);
      expect(find.textContaining('SECRETO'), findsNothing);
      expect(find.textContaining('USUARIO'), findsNothing);
    });

    testWidgets('sin nombre usa el servidor, y eliminar pide confirmación', (tester) async {
      await tester.pumpWidget(app(const IPTVManagerScreen()));
      await tester.tap(find.text('AÑADIR LISTA'));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'URL de la lista'), 'https://lista.example/canales.m3u');
      await tester.tap(find.text('AÑADIR'));
      await tester.pumpAndSettle();
      expect(IPTVService.instance.playlists.single.nombre, 'lista.example');
      expect(IPTVService.instance.playlists.single.tipo, IPTVType.m3u);

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      expect(find.text('Eliminar lista'), findsOneWidget);
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();
      expect(IPTVService.instance.playlists.length, 1);

      await tester.tap(find.byTooltip('Eliminar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINAR'));
      await tester.pumpAndSettle();
      expect(IPTVService.instance.playlists, isEmpty);
      expect(find.text('Aún no tienes listas'), findsOneWidget);
    });

    testWidgets('las listas se guardan y se recuperan', (tester) async {
      await IPTVService.instance.add(nombre: 'Persistente', url: xtreamUrl);
      await IPTVService.instance.load(); // vuelve a leer de shared_preferences
      expect(IPTVService.instance.playlists.single.nombre, 'Persistente');
      expect(IPTVService.instance.playlists.single.url, xtreamUrl);
    });
  });

  group('IPTVChannelListScreen', () {
    // 150 000 entradas en 250 grupos: el tamaño de una lista real grande.
    final channels = [
      for (var g = 0; g < 250; g++)
        for (var i = 0; i < 600; i++)
          Channel(nombre: 'Canal $g-$i', url: 'http://srv/$g/$i', grupo: 'Grupo $g'),
    ];

    Future<IPTVPlaylist> seeded() async {
      final p = await IPTVService.instance.add(nombre: 'Grande', url: 'http://srv/l.m3u');
      IPTVService.instance.seedChannels(p.id, channels);
      return p;
    }

    testWidgets('muestra los grupos cerrados, expande uno y lista sus canales', (tester) async {
      final p = await seeded();
      await tester.pumpWidget(app(IPTVChannelListScreen(playlist: p)));
      await tester.pumpAndSettle();

      expect(find.text('Buscar entre 150000 canales'), findsOneWidget);
      expect(find.text('Grupo 0'), findsOneWidget);
      expect(find.text('600'), findsWidgets); // contador del grupo
      expect(find.text('Canal 0-0'), findsNothing); // cerrado: no hay canales

      await tester.tap(find.text('Grupo 0'));
      await tester.pumpAndSettle();
      expect(find.text('Canal 0-0'), findsOneWidget);

      await tester.tap(find.text('Grupo 0')); // se vuelve a cerrar
      await tester.pumpAndSettle();
      expect(find.text('Canal 0-0'), findsNothing);
    });

    testWidgets('buscar filtra entre todos los canales y limita los resultados', (tester) async {
      final p = await seeded();
      await tester.pumpWidget(app(IPTVChannelListScreen(playlist: p)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'canal 249-599');
      await tester.pump(const Duration(milliseconds: 400)); // espera el debounce
      await tester.pumpAndSettle();
      expect(find.text('Canal 249-599'), findsOneWidget);
      expect(find.text('Grupo 249'), findsOneWidget); // en búsqueda se enseña el grupo de cada canal

      await tester.enterText(find.byType(TextField), 'canal'); // 150 000 coincidencias
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('primeros 500 resultados'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'zzzz-no-existe');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Sin resultados'), findsOneWidget);
    });
  });
}
