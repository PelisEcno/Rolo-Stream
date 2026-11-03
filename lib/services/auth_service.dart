import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';

class AppUser {
  final String uid;
  final String? nombre;
  final String? email;
  const AppUser({required this.uid, this.nombre, this.email});

  /// Dueño de los datos cuando la app se usa sin cuenta.
  static const local = AppUser(uid: 'local');
}

/// Error con un mensaje listo para mostrar al usuario.
class AuthFailure implements Exception {
  final String message;
  const AuthFailure(this.message);

  @override
  String toString() => message;
}

/// Sesión del usuario. Firebase la recuerda entre aperturas de la app.
///
/// Sin un proyecto de Firebase conectado ([firebaseReady] es `false`) no hay login posible y se
/// ofrece usar la app sin cuenta, para que una build sin configurar no quede bloqueada.
class AuthService extends ChangeNotifier {
  AuthService._();
  static final instance = AuthService._();

  static const _localKey = 'auth_local_mode';

  bool _firebaseReady = false;
  AppUser? _user;
  StreamSubscription<User?>? _sub;

  bool get firebaseReady => _firebaseReady;
  AppUser? get user => _user;
  bool get isLocal => _user?.uid == AppUser.local.uid;

  Future<void> init() async {
    try {
      final options = DefaultFirebaseOptions.currentPlatform;
      await Firebase.initializeApp(options: options);
      await GoogleSignIn.instance.initialize(
        clientId: defaultTargetPlatform == TargetPlatform.iOS ? options.iosClientId : null,
      );
      _firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase no disponible: $e');
      _firebaseReady = false;
    }

    final prefs = await SharedPreferences.getInstance();
    if (_firebaseReady) {
      await prefs.remove(_localKey);
      _setFirebaseUser(FirebaseAuth.instance.currentUser);
      _sub = FirebaseAuth.instance.authStateChanges().listen(_setFirebaseUser);
    } else if (prefs.getBool(_localKey) ?? false) {
      _user = AppUser.local;
    }
    notifyListeners();
  }

  void _setFirebaseUser(User? u) {
    final next = u == null ? null : AppUser(uid: u.uid, nombre: u.displayName, email: u.email);
    final changed = next?.uid != _user?.uid;
    _user = next;
    if (changed) notifyListeners();
  }

  /// Inicia sesión con Google. Si el usuario cancela vuelve sin hacer nada.
  Future<void> signInWithGoogle() async {
    if (!_firebaseReady) {
      throw const AuthFailure('El inicio de sesión aún no está configurado en esta versión.');
    }
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const AuthFailure('Google no devolvió las credenciales. Inténtalo de nuevo.');
      }
      await FirebaseAuth.instance
          .signInWithCredential(GoogleAuthProvider.credential(idToken: idToken));
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      debugPrint('Google Sign-In: ${e.code} ${e.description}');
      throw AuthFailure(switch (e.code) {
        GoogleSignInExceptionCode.clientConfigurationError ||
        GoogleSignInExceptionCode.providerConfigurationError =>
          'El inicio de sesión con Google no está bien configurado en esta versión.',
        _ => 'No se pudo iniciar sesión con Google. Inténtalo de nuevo.',
      });
    } on FirebaseAuthException catch (e) {
      debugPrint('Firebase Auth: ${e.code}');
      throw AuthFailure(switch (e.code) {
        'network-request-failed' => 'Sin conexión. Revisa tu internet e inténtalo de nuevo.',
        'user-disabled' => 'Esta cuenta está deshabilitada.',
        _ => 'No se pudo iniciar sesión. Inténtalo de nuevo.',
      });
    }
  }

  /// Solo disponible mientras no haya Firebase: ver la nota de la clase.
  Future<void> continueWithoutAccount() async {
    if (_firebaseReady) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_localKey, true);
    _user = AppUser.local;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_firebaseReady) {
      await GoogleSignIn.instance.signOut();
      await FirebaseAuth.instance.signOut();
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localKey);
    }
    _user = null;
    notifyListeners();
  }

  /// Solo para pruebas: fija el estado sin pasar por Firebase.
  @visibleForTesting
  void debugSet({required bool firebaseReady, AppUser? user}) {
    _sub?.cancel();
    _sub = null;
    _firebaseReady = firebaseReady;
    _user = user;
    notifyListeners();
  }
}
