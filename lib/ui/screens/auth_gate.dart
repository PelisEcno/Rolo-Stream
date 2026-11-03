import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'profile_selection_screen.dart';

/// Decide qué se ve al abrir la app: login, "¿Quién está viendo?" o el inicio.
class AuthGate extends StatefulWidget {
  /// Pantalla principal. Solo se cambia en las pruebas.
  final Widget Function(Profile profile) homeBuilder;
  const AuthGate({super.key, this.homeBuilder = _defaultHome});

  static Widget _defaultHome(Profile p) => HomeShell(key: ValueKey(p.id));

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService.instance;
  final _profiles = ProfileService.instance;

  @override
  void initState() {
    super.initState();
    _auth.addListener(_syncProfiles);
    _syncProfiles();
  }

  @override
  void dispose() {
    _auth.removeListener(_syncProfiles);
    super.dispose();
  }

  /// Cada cuenta tiene sus perfiles: se cargan al cambiar de usuario.
  void _syncProfiles() {
    final uid = _auth.user?.uid;
    if (uid == _profiles.loadedUid) return;
    if (uid == null) {
      _profiles.unload();
    } else {
      _profiles.loadFor(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _profiles]),
      builder: (context, _) {
        final user = _auth.user;
        if (user == null) return const LoginScreen();
        if (_profiles.loadedUid != user.uid) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final active = _profiles.active;
        if (active == null) return const ProfileSelectionScreen();
        return widget.homeBuilder(active);
      },
    );
  }
}
