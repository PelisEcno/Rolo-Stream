import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'iptv_models.dart';
import 'm3u_parser.dart';

/// Listas IPTV del usuario, guardadas en `shared_preferences`, y descarga de sus canales.
///
/// Las URLs suelen llevar usuario y contraseña (Xtream Codes): se guardan tal cual en el
/// almacenamiento de la app y la UI nunca las muestra completas.
class IPTVService extends ChangeNotifier {
  IPTVService._();
  static final instance = IPTVService._();

  static const _key = 'iptv_playlists';

  final List<IPTVPlaylist> _playlists = [];
  final Map<String, List<Channel>> _cache = {};

  List<IPTVPlaylist> get playlists => List.unmodifiable(_playlists);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _playlists
      ..clear()
      ..addAll([
        for (final raw in prefs.getStringList(_key) ?? const <String>[])
          IPTVPlaylist.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      ]);
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final p in _playlists) jsonEncode(p.toJson())]);
  }

  /// Valida que [url] sea una URL http(s). Devuelve el motivo del error o `null` si es válida.
  static String? validateUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      return 'Escribe una URL que empiece por http:// o https://';
    }
    return null;
  }

  Future<IPTVPlaylist> add({required String nombre, required String url}) async {
    final clean = url.trim();
    final playlist = IPTVPlaylist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      nombre: nombre.trim().isEmpty ? (Uri.parse(clean).host) : nombre.trim(),
      url: clean,
      tipo: IPTVPlaylist.detectType(clean),
    );
    _playlists.add(playlist);
    notifyListeners();
    await _save();
    return playlist;
  }

  Future<void> remove(String id) async {
    _playlists.removeWhere((p) => p.id == id);
    _cache.remove(id);
    notifyListeners();
    await _save();
  }

  /// Solo para pruebas: deja canales ya cargados, sin descargar nada.
  @visibleForTesting
  void seedChannels(String playlistId, List<Channel> channels) => _cache[playlistId] = channels;

  /// Descarga y parsea los canales de [playlist]. El resultado se guarda en memoria mientras
  /// la app esté abierta; [refresh] fuerza una descarga nueva.
  Future<List<Channel>> channelsFor(IPTVPlaylist playlist, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(playlist.id)) return _cache[playlist.id]!;

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 90),
      followRedirects: true,
      responseType: ResponseType.bytes,
      // Muchos paneles IPTV solo responden a clientes que se presentan como reproductores.
      headers: {'User-Agent': 'VLC/3.0.20 LibVLC/3.0.20'},
      validateStatus: (_) => true,
    ));

    try {
      final res = await dio.get<List<int>>(playlist.url);
      final status = res.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw IPTVException(switch (status) {
          401 || 403 => 'El servidor rechazó la lista (HTTP $status). Revisa el usuario y la contraseña.',
          404 => 'La lista no existe en esa URL (HTTP 404).',
          _ => 'El servidor respondió HTTP $status.',
        });
      }
      final text = utf8.decode(res.data ?? const [], allowMalformed: true);
      if (!text.contains('#EXTINF') && !text.contains('://')) {
        throw const IPTVException('La respuesta no parece una lista M3U.');
      }
      // Las listas grandes (decenas de miles de canales) se parsean fuera del hilo de la UI.
      final channels = await compute(parseM3U, text);
      if (channels.isEmpty) {
        throw const IPTVException('La lista no tiene ningún canal.');
      }
      _cache[playlist.id] = channels;
      return channels;
    } on DioException catch (e) {
      throw IPTVException(switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          'Tiempo de espera agotado al descargar la lista.',
        DioExceptionType.connectionError => 'No se pudo conectar con el servidor de la lista.',
        _ => 'Error de red al descargar la lista.',
      });
    } finally {
      dio.close();
    }
  }
}

/// Error con un mensaje listo para mostrar al usuario.
class IPTVException implements Exception {
  final String message;
  const IPTVException(this.message);

  @override
  String toString() => message;
}
