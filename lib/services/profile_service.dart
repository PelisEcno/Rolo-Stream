import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'watch_progress_service.dart';

class Profile {
  final String id;
  final String nombre;

  /// Índice en [kProfileAvatars] (ver `profile_avatar.dart`).
  final int avatar;

  const Profile({required this.id, required this.nombre, this.avatar = 0});

  Map<String, dynamic> toJson() => {'id': id, 'nombre': nombre, 'avatar': avatar};

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: '${j['id'] ?? ''}',
        nombre: '${j['nombre'] ?? ''}',
        avatar: j['avatar'] is int ? j['avatar'] as int : 0,
      );
}

/// Perfiles de cada cuenta, guardados en este dispositivo.
class ProfileService extends ChangeNotifier {
  ProfileService();
  static final instance = ProfileService();

  static const maxProfiles = 4;

  final List<Profile> _profiles = [];
  String? _uid;
  Profile? _active;

  List<Profile> get profiles => List.unmodifiable(_profiles);
  Profile? get active => _active;
  String? get loadedUid => _uid;
  bool get canAdd => _profiles.length < maxProfiles;

  static String _key(String uid) => 'profiles_$uid';

  /// Carga los perfiles de la cuenta [uid]. Siempre vuelve a preguntar quién está viendo.
  Future<void> loadFor(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    _uid = uid;
    _active = null;
    _profiles
      ..clear()
      ..addAll([
        for (final raw in prefs.getStringList(_key(uid)) ?? const <String>[])
          Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      ]);
    notifyListeners();
  }

  /// Olvida la cuenta cargada al cerrar sesión. Sus perfiles siguen guardados.
  void unload() {
    _uid = null;
    _active = null;
    _profiles.clear();
    notifyListeners();
  }

  Future<void> _save() async {
    final uid = _uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(uid), [for (final p in _profiles) jsonEncode(p.toJson())]);
  }

  Future<Profile> add({required String nombre, required int avatar}) async {
    if (!canAdd) throw StateError('Máximo $maxProfiles perfiles');
    // El reloj puede repetir valor entre dos llamadas seguidas.
    var stamp = DateTime.now().microsecondsSinceEpoch;
    while (_profiles.any((p) => p.id == '$stamp')) {
      stamp++;
    }
    final profile = Profile(
      id: '$stamp',
      nombre: nombre.trim(),
      avatar: avatar,
    );
    _profiles.add(profile);
    notifyListeners();
    await _save();
    return profile;
  }

  Future<void> update(String id, {required String nombre, required int avatar}) async {
    final i = _profiles.indexWhere((p) => p.id == id);
    if (i < 0) return;
    _profiles[i] = Profile(id: id, nombre: nombre.trim(), avatar: avatar);
    notifyListeners();
    await _save();
  }

  /// Elimina el perfil y su progreso.
  Future<void> remove(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    if (_active?.id == id) _active = null;
    notifyListeners();
    await _save();
    await WatchProgressService.instance.deleteFor(id);
  }

  Future<void> select(Profile profile) async {
    await WatchProgressService.instance.loadFor(profile.id);
    _active = profile;
    notifyListeners();
  }

  /// Vuelve a la pantalla de "¿Quién está viendo?".
  void clearActive() {
    _active = null;
    notifyListeners();
  }
}
