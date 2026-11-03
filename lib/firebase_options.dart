import 'package:firebase_core/firebase_core.dart';

/// Marcador hasta conectar un proyecto de Firebase. `flutterfire configure` reemplaza este archivo
/// por el definitivo, con la misma API. Mientras tanto la app funciona sin cuentas: ver
/// [AuthService.firebaseReady].
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase sin configurar: ejecuta `flutterfire configure`.');
}
