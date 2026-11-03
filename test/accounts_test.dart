import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rolostream/firebase_options.dart';
import 'package:rolostream/services/auth_service.dart';
import 'package:rolostream/services/profile_service.dart';
import 'package:rolostream/services/watch_progress_service.dart';
import 'package:rolostream/ui/screens/auth_gate.dart';
import 'package:rolostream/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const min = Duration(minutes: 1);

Future<void> saveEp(
  WatchProgressService svc, {
  String slug = 'naruto',
  int numero = 1,
  Duration position = const Duration(minutes: 10),
  Duration duration = const Duration(minutes: 24),
  DateTime? now,
}) =>
    svc.save(
      sourceId: 'src',
      slug: slug,
      numero: numero,
      titulo: slug,
      imagen: 'http://img/$slug',
      position: position,
      duration: duration,
      now: now,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WatchProgressService', () {
    late WatchProgressService svc;
    setUp(() async {
      svc = WatchProgressService();
      await svc.loadFor('perfil-a');
    });

    test('guarda y da el punto donde reanudar', () async {
      await saveEp(svc);
      expect(svc.resumePoint('src', 'naruto', 1), const Duration(minutes: 10));
      expect(svc.resumePoint('src', 'naruto', 2), isNull);
      expect(svc.resumePoint('otra', 'naruto', 1), isNull);
    });

    test('sobrevive a cerrar la app', () async {
      await saveEp(svc);
      final otra = WatchProgressService();
      await otra.loadFor('perfil-a');
      expect(otra.resumePoint('src', 'naruto', 1), const Duration(minutes: 10));
      expect(otra.continueWatching().single.fraction, closeTo(10 / 24, 1e-9));
    });

    test('cada perfil tiene su propio progreso', () async {
      await saveEp(svc);
      await svc.loadFor('perfil-b');
      expect(svc.resumePoint('src', 'naruto', 1), isNull);
      expect(svc.continueWatching(), isEmpty);
      await svc.loadFor('perfil-a');
      expect(svc.resumePoint('src', 'naruto', 1), isNotNull);
    });

    test('abrir un episodio y salir enseguida no cuenta', () async {
      await saveEp(svc, position: const Duration(seconds: 14));
      expect(svc.resumePoint('src', 'naruto', 1), isNull);
    });

    test('al terminar, por los créditos o el 95 %, sale de Seguir viendo', () async {
      await saveEp(svc);
      await saveEp(svc, position: const Duration(minutes: 22, seconds: 45)); // quedan 75 s
      expect(svc.resumePoint('src', 'naruto', 1), isNull);
      expect(svc.continueWatching(), isEmpty);

      await saveEp(svc, slug: 'peli', duration: const Duration(minutes: 120), position: const Duration(minutes: 115));
      expect(svc.resumePoint('src', 'peli', 1), isNull);
    });

    test('sin duración conocida (o sin perfil) no guarda nada', () async {
      await saveEp(svc, duration: Duration.zero);
      expect(svc.continueWatching(), isEmpty);

      final sinPerfil = WatchProgressService();
      await saveEp(sinPerfil);
      expect(sinPerfil.continueWatching(), isEmpty);
    });

    test('Seguir viendo: una tarjeta por serie, la más reciente primero', () async {
      final t0 = DateTime.utc(2026, 11, 2, 10);
      await saveEp(svc, slug: 'naruto', numero: 1, now: t0);
      await saveEp(svc, slug: 'bleach', numero: 3, now: t0.add(const Duration(hours: 1)));
      await saveEp(svc, slug: 'naruto', numero: 2, now: t0.add(const Duration(hours: 2)));

      final items = svc.continueWatching();
      expect(items.map((p) => '${p.slug} ${p.numero}'), ['naruto 2', 'bleach 3']);
    });

    test('conserva la carátula si se vuelve a entrar sin ella', () async {
      await saveEp(svc);
      await svc.save(
          sourceId: 'src',
          slug: 'naruto',
          numero: 1,
          titulo: 'naruto',
          imagen: '',
          position: const Duration(minutes: 11),
          duration: const Duration(minutes: 24));
      expect(svc.continueWatching().single.imagen, 'http://img/naruto');
    });

    test('deleteFor borra el progreso del perfil', () async {
      await saveEp(svc);
      await svc.deleteFor('perfil-a');
      final otra = WatchProgressService();
      await otra.loadFor('perfil-a');
      expect(otra.continueWatching(), isEmpty);
    });
  });

  group('ProfileService', () {
    late ProfileService svc;
    setUp(() async {
      svc = ProfileService();
      await svc.loadFor('uid-1');
    });

    test('permite hasta 4 perfiles', () async {
      for (var i = 0; i < 4; i++) {
        await svc.add(nombre: 'P$i', avatar: i);
      }
      expect(svc.canAdd, isFalse);
      expect(() => svc.add(nombre: 'P5', avatar: 0), throwsStateError);
      expect(svc.profiles.length, 4);
    });

    test('se guardan por cuenta', () async {
      await svc.add(nombre: '  Ana ', avatar: 2);
      await svc.loadFor('uid-2');
      expect(svc.profiles, isEmpty);
      await svc.loadFor('uid-1');
      expect(svc.profiles.single.nombre, 'Ana');
      expect(svc.profiles.single.avatar, 2);
      expect(svc.active, isNull); // siempre pregunta quién está viendo
    });

    test('editar y eliminar', () async {
      final p = await svc.add(nombre: 'Ana', avatar: 0);
      await svc.update(p.id, nombre: 'Anita', avatar: 5);
      expect(svc.profiles.single.nombre, 'Anita');
      expect(svc.profiles.single.avatar, 5);
      await svc.remove(p.id);
      expect(svc.profiles, isEmpty);
    });
  });

  test('sin configurar, las opciones de Firebase avisan en vez de romper la compilación', () {
    expect(() => DefaultFirebaseOptions.currentPlatform, throwsUnsupportedError);
  });

  group('AuthGate', () {
    final auth = AuthService.instance;
    final profiles = ProfileService.instance;

    Future<void> open(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(homeBuilder: (p) => Text('INICIO de ${p.nombre}')),
      ));
      await tester.pumpAndSettle();
    }

    setUp(() {
      profiles.unload();
      auth.debugSet(firebaseReady: false);
    });

    testWidgets('con Firebase: pide Google y no ofrece entrar sin cuenta', (tester) async {
      auth.debugSet(firebaseReady: true);
      await open(tester);
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(find.text('CONTINUAR SIN CUENTA'), findsNothing);
    });

    testWidgets('sesión recordada: va directo a elegir perfil', (tester) async {
      auth.debugSet(firebaseReady: true, user: const AppUser(uid: 'u1', email: 'a@b.c'));
      await open(tester);
      expect(find.text('¿Quién está viendo?'), findsOneWidget);
      expect(find.text('Continuar con Google'), findsNothing);
    });

    testWidgets('sin Firebase se puede entrar, crear perfil y llegar al inicio', (tester) async {
      await open(tester);
      expect(find.text('Continuar con Google'), findsNothing);

      await tester.tap(find.text('CONTINUAR SIN CUENTA'));
      await tester.pumpAndSettle();
      expect(find.text('¿Quién está viendo?'), findsOneWidget);

      await tester.tap(find.text('Añadir perfil'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('GUARDAR')); // sin nombre no deja
      await tester.pump();
      expect(find.text('Escribe un nombre'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Ana');
      await tester.tap(find.byKey(const ValueKey('avatar-3')));
      await tester.pump();
      await tester.tap(find.text('GUARDAR'));
      await tester.pumpAndSettle();
      expect(profiles.profiles.single.avatar, 3);

      await tester.tap(find.text('Ana'));
      await tester.pumpAndSettle();
      expect(find.text('INICIO de Ana'), findsOneWidget);

      profiles.clearActive(); // "Cambiar de perfil"
      await tester.pumpAndSettle();
      expect(find.text('¿Quién está viendo?'), findsOneWidget);
    });

    testWidgets('con 4 perfiles desaparece Añadir; administrar permite eliminar', (tester) async {
      auth.debugSet(firebaseReady: true, user: const AppUser(uid: 'u4'));
      await open(tester);
      for (var i = 0; i < 4; i++) {
        await profiles.add(nombre: 'P$i', avatar: i);
      }
      await tester.pumpAndSettle();
      expect(find.text('Añadir perfil'), findsNothing);

      await tester.tap(find.text('Administrar perfiles'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('P0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINAR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ELIMINAR').last);
      await tester.pumpAndSettle();
      expect(profiles.profiles.length, 3);

      await tester.tap(find.text('LISTO'));
      await tester.pumpAndSettle();
      expect(find.text('Añadir perfil'), findsOneWidget);
    });

    testWidgets('al cerrar sesión vuelve al login', (tester) async {
      auth.debugSet(firebaseReady: true, user: const AppUser(uid: 'u5'));
      await open(tester);
      auth.debugSet(firebaseReady: true);
      await tester.pumpAndSettle();
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(profiles.loadedUid, isNull);
    });
  });
}
