import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hasta dónde se vio un episodio.
class WatchProgress {
  final String sourceId;
  final String slug;
  final int numero;
  final String titulo;
  final String imagen;
  final Duration position;
  final Duration duration;
  final DateTime updatedAt;

  const WatchProgress({
    required this.sourceId,
    required this.slug,
    required this.numero,
    required this.titulo,
    required this.imagen,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  /// Fracción vista, de 0.0 a 1.0.
  double get fraction => duration.inMilliseconds <= 0
      ? 0
      : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'slug': slug,
        'numero': numero,
        'titulo': titulo,
        'imagen': imagen,
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory WatchProgress.fromJson(Map<String, dynamic> j) => WatchProgress(
        sourceId: '${j['sourceId'] ?? ''}',
        slug: '${j['slug'] ?? ''}',
        numero: j['numero'] is int ? j['numero'] as int : 0,
        titulo: '${j['titulo'] ?? ''}',
        imagen: '${j['imagen'] ?? ''}',
        position: Duration(milliseconds: j['position'] is int ? j['position'] as int : 0),
        duration: Duration(milliseconds: j['duration'] is int ? j['duration'] as int : 0),
        updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// Comprueba que el video de verdad haya arrancado donde tocaba.
///
/// `Media.start` no siempre se cumple (depende de la fuente, sobre todo en HLS), y mientras no se
/// sepa no hay que guardar progreso: un arranque en 0 borraría el punto guardado.
class ResumeGuard {
  final Duration target;
  ResumeGuard(this.target);

  static const _tolerance = Duration(seconds: 5);
  static const _retryAfter = Duration(seconds: 8);
  static const _maxSeeks = 3;

  bool done = false;
  bool gaveUp = false;
  int seeks = 0;
  DateTime? _lastSeek;

  /// Con el video ya avanzando: devuelve a dónde saltar, o `null` si no hay que hacer nada.
  Duration? check(Duration position, DateTime now) {
    if (done) return null;
    if (position >= target - _tolerance) {
      done = true;
      return null;
    }
    final last = _lastSeek;
    if (last != null && now.difference(last) < _retryAfter) return null;
    if (seeks >= _maxSeeks) {
      done = true;
      gaveUp = true;
      return null;
    }
    seeks++;
    _lastSeek = now;
    return target;
  }
}

/// Progreso de reproducción del perfil activo, guardado en este dispositivo.
class WatchProgressService extends ChangeNotifier {
  WatchProgressService();
  static final instance = WatchProgressService();

  /// Por debajo de esto no se guarda: abrir un episodio y salir no es "dejarlo a medias".
  static const minPosition = Duration(seconds: 15);

  /// Se considera visto si queda menos de esto (los créditos) o más del 95 %.
  static const finishedRemaining = Duration(seconds: 90);
  static const finishedFraction = 0.95;

  static const _maxEntries = 100;

  final Map<String, WatchProgress> _entries = {};
  String? _profileId;

  static String _prefsKey(String profileId) => 'watch_progress_$profileId';
  static String _entryKey(String sourceId, String slug, int numero) => '$sourceId|$slug|$numero';

  Future<void> loadFor(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    _profileId = profileId;
    _entries.clear();
    for (final raw in prefs.getStringList(_prefsKey(profileId)) ?? const <String>[]) {
      final p = WatchProgress.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _entries[_entryKey(p.sourceId, p.slug, p.numero)] = p;
    }
    notifyListeners();
  }

  Future<void> deleteFor(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey(profileId));
    if (_profileId == profileId) {
      _profileId = null;
      _entries.clear();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    final id = _profileId;
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _prefsKey(id), [for (final p in _entries.values) jsonEncode(p.toJson())]);
  }

  /// Punto donde reanudar un episodio, o `null` si no hay progreso guardado.
  Duration? resumePoint(String sourceId, String slug, int numero) =>
      _entries[_entryKey(sourceId, slug, numero)]?.position;

  /// Registra la posición actual. Un episodio terminado se quita de "Seguir viendo".
  Future<void> save({
    required String sourceId,
    required String slug,
    required int numero,
    required String titulo,
    required String imagen,
    required Duration position,
    required Duration duration,
    DateTime? now,
  }) async {
    if (_profileId == null || duration <= Duration.zero) return;
    final key = _entryKey(sourceId, slug, numero);

    final finished = duration - position < finishedRemaining ||
        position.inMilliseconds / duration.inMilliseconds >= finishedFraction;
    if (finished) {
      if (_entries.remove(key) != null) {
        notifyListeners();
        await _persist();
      }
      return;
    }
    if (position < minPosition) return;

    _entries[key] = WatchProgress(
      sourceId: sourceId,
      slug: slug,
      numero: numero,
      titulo: titulo,
      // Se puede entrar a un episodio sin carátula: se conserva la que ya hubiera.
      imagen: imagen.isNotEmpty ? imagen : (_entries[key]?.imagen ?? ''),
      position: position,
      duration: duration,
      updatedAt: now ?? DateTime.now(),
    );
    _trim();
    notifyListeners();
    await _persist();
  }

  void _trim() {
    if (_entries.length <= _maxEntries) return;
    final oldest = _entries.entries.toList()
      ..sort((a, b) => a.value.updatedAt.compareTo(b.value.updatedAt));
    for (final e in oldest.take(_entries.length - _maxEntries)) {
      _entries.remove(e.key);
    }
  }

  /// Para "Seguir viendo": el último episodio visto de cada serie, del más reciente al más antiguo.
  List<WatchProgress> continueWatching() {
    final latest = <String, WatchProgress>{};
    for (final p in _entries.values) {
      final series = '${p.sourceId}|${p.slug}';
      final current = latest[series];
      if (current == null || p.updatedAt.isAfter(current.updatedAt)) latest[series] = p;
    }
    return latest.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}
