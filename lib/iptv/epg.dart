import 'package:flutter/foundation.dart';

import 'iptv_models.dart';

/// Un programa de la guía de programación (EPG).
class EPGProgram {
  final String titulo;
  final DateTime inicio;
  final DateTime fin;
  final String? descripcion;

  EPGProgram({
    required this.titulo,
    required this.inicio,
    required this.fin,
    this.descripcion,
  }) : assert(!fin.isBefore(inicio), 'fin no puede ser anterior a inicio');

  Duration get duracion => fin.difference(inicio);

  /// `true` si [now] cae dentro del programa (inicio incluido, fin excluido).
  bool isLiveAt(DateTime now) => !now.isBefore(inicio) && now.isBefore(fin);

  /// Fracción emitida de 0.0 a 1.0 (0 si aún no empieza, 1 si ya terminó).
  double progressAt(DateTime now) {
    final total = duracion.inMilliseconds;
    if (total <= 0) return 0;
    final done = now.difference(inicio).inMilliseconds;
    return (done / total).clamp(0.0, 1.0);
  }

  /// Hora local en formato `HH:mm`.
  static String hora(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String get rango => '${hora(inicio)} - ${hora(fin)}';

  Map<String, dynamic> toJson() => {
        'titulo': titulo,
        'inicio': inicio.toUtc().toIso8601String(),
        'fin': fin.toUtc().toIso8601String(),
        if (descripcion != null) 'descripcion': descripcion,
      };

  factory EPGProgram.fromJson(Map<String, dynamic> j) => EPGProgram(
        titulo: '${j['titulo'] ?? ''}',
        inicio: DateTime.parse('${j['inicio']}'),
        fin: DateTime.parse('${j['fin']}'),
        descripcion: j['descripcion'] as String?,
      );
}

/// Lo que se emite ahora en un canal y lo siguiente.
class NowNext {
  final EPGProgram? ahora;
  final EPGProgram? despues;
  const NowNext(this.ahora, this.despues);

  bool get isEmpty => ahora == null && despues == null;
}

/// Programación de un canal, ordenada por hora de inicio.
class EPGSchedule {
  final List<EPGProgram> programas;

  EPGSchedule(Iterable<EPGProgram> programas)
      : programas = List.unmodifiable([...programas]..sort((a, b) => a.inicio.compareTo(b.inicio)));

  bool get isEmpty => programas.isEmpty;

  /// Programa en emisión en [now] y el primero que empiece después de él.
  NowNext nowNext(DateTime now) {
    EPGProgram? ahora;
    EPGProgram? despues;
    for (final p in programas) {
      if (p.isLiveAt(now)) {
        ahora = p;
      } else if (p.inicio.isAfter(now) || p.inicio.isAtSameMomentAs(now)) {
        despues = p;
        break;
      }
    }
    return NowNext(ahora, despues);
  }
}

/// Guía de programación en memoria, indexada por `tvg-id`.
///
/// Todavía no se descarga ningún XMLTV: cuando exista el lector, solo tiene que llamar a
/// [setAll] con los programas de cada canal y la UI se actualiza sola.
class EPGService extends ChangeNotifier {
  EPGService();
  static final instance = EPGService();

  final Map<String, EPGSchedule> _byChannel = {};

  bool get hasData => _byChannel.isNotEmpty;

  void setSchedule(String tvgId, Iterable<EPGProgram> programas) {
    _byChannel[tvgId] = EPGSchedule(programas);
    notifyListeners();
  }

  /// Carga la guía completa de una vez: la UI se repinta una sola vez, no una por canal.
  void setAll(Map<String, Iterable<EPGProgram>> guia) {
    for (final e in guia.entries) {
      _byChannel[e.key] = EPGSchedule(e.value);
    }
    notifyListeners();
  }

  void clear() {
    _byChannel.clear();
    notifyListeners();
  }

  EPGSchedule? scheduleFor(Channel c) => c.tvgId == null ? null : _byChannel[c.tvgId];

  /// Ahora / después de [c], o `null` si el canal no tiene datos de guía.
  NowNext? nowNextFor(Channel c, {DateTime? now}) {
    final s = scheduleFor(c);
    if (s == null) return null;
    final nn = s.nowNext(now ?? DateTime.now());
    return nn.isEmpty ? null : nn;
  }
}
