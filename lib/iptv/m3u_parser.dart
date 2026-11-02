import 'iptv_models.dart';

final _attrRe = RegExp(r'''([A-Za-z0-9_\-]+)\s*=\s*"([^"]*)"''');

/// Lee una lista M3U / M3U8 y devuelve sus canales, en el orden de la lista.
///
/// ```
/// #EXTM3U
/// #EXTINF:-1 tvg-logo="http://x/logo.png" group-title="Noticias",Nombre del canal
/// #EXTVLCOPT:http-user-agent=Mozilla/5.0      (opcional)
/// http://servidor/canal.m3u8
/// ```
///
/// Tolera: BOM, finales de línea `\r\n`, comas dentro de los atributos entrecomillados,
/// `#EXTGRP:` como grupo de respaldo, `tvg-name` cuando no hay nombre tras la coma,
/// y líneas sueltas con una URL (sin `#EXTINF`). Es Dart puro, para poder usarlo con `compute`.
List<Channel> parseM3U(String content) {
  final out = <Channel>[];

  String? nombre;
  String? logo;
  String? grupo;
  String? extGrp;
  var headers = <String, String>{};
  var pending = false; // hay un #EXTINF esperando su URL

  void reset() {
    nombre = logo = grupo = extGrp = null;
    headers = <String, String>{};
    pending = false;
  }

  var first = true;
  for (var raw in content.split(RegExp(r'\r\n|\n|\r'))) {
    if (first) {
      first = false;
      if (raw.startsWith('﻿')) raw = raw.substring(1);
    }
    final line = raw.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('#')) {
      final upper = line.toUpperCase();
      if (upper.startsWith('#EXTINF:')) {
        reset();
        pending = true;
        final body = line.substring(8);
        final comma = _firstCommaOutsideQuotes(body);
        final attrsPart = comma < 0 ? body : body.substring(0, comma);
        final namePart = comma < 0 ? '' : body.substring(comma + 1).trim();
        final attrs = <String, String>{
          for (final m in _attrRe.allMatches(attrsPart)) m.group(1)!.toLowerCase(): m.group(2)!.trim(),
        };
        nombre = namePart.isNotEmpty ? namePart : attrs['tvg-name'];
        logo = _nonEmpty(attrs['tvg-logo']);
        grupo = _nonEmpty(attrs['group-title']);
      } else if (upper.startsWith('#EXTGRP:')) {
        extGrp = _nonEmpty(line.substring(8).trim());
      } else if (upper.startsWith('#EXTVLCOPT:')) {
        final opt = line.substring(11);
        final eq = opt.indexOf('=');
        if (eq > 0) {
          final key = opt.substring(0, eq).trim().toLowerCase();
          final value = opt.substring(eq + 1).trim();
          if (value.isNotEmpty) {
            if (key == 'http-user-agent') headers['User-Agent'] = value;
            if (key == 'http-referrer' || key == 'http-referer') headers['Referer'] = value;
          }
        }
      }
      continue; // #EXTM3U y demás comentarios
    }

    // Línea con la URL del canal.
    if (!line.contains('://')) {
      reset();
      continue;
    }
    out.add(Channel(
      nombre: _nonEmpty(nombre) ?? (pending ? 'Canal sin nombre' : _nameFromUrl(line)),
      logo: logo,
      grupo: grupo ?? extGrp ?? Channel.sinGrupo,
      url: line,
      headers: headers,
    ));
    reset();
  }
  return out;
}

/// Agrupa los canales por `group-title`, respetando el orden de aparición.
Map<String, List<Channel>> groupChannels(List<Channel> channels) {
  final groups = <String, List<Channel>>{};
  for (final c in channels) {
    (groups[c.grupo] ??= <Channel>[]).add(c);
  }
  return groups;
}

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Índice de la primera coma que no está dentro de comillas (los atributos pueden traer comas).
int _firstCommaOutsideQuotes(String s) {
  var inQuotes = false;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c == 0x22) {
      inQuotes = !inQuotes;
    } else if (c == 0x2C && !inQuotes) {
      return i;
    }
  }
  return -1;
}

String _nameFromUrl(String url) {
  final uri = Uri.tryParse(url);
  final last = uri?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  return last ?? uri?.host ?? url;
}
