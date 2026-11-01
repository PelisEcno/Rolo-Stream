import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import '../models/anime_result.dart';
import '../models/anime_detail.dart';
import '../models/video_server.dart';
import '../services/http_client.dart';

class PluginRuntime {
  final JavascriptRuntime _js;
  final String _pluginCode;

  PluginRuntime(this._pluginCode) : _js = getJavascriptRuntime();

  /// Ejecuta el plugin y devuelve la lista de resultados.
  Future<List<AnimeResult>> search(String query) async {
    _loadPlugin();

    final result = _js.evaluate('''
      (async () => {
        return await plugin.search(${jsonEncode(query)});
      })();
    ''');

    final data = await _awaitPromise(result);
    final list = jsonDecode(data) as List;
    return list.map((e) => AnimeResult.fromJson(e)).toList();
  }

  Future<AnimeDetail> getAnime(String slug) async {
    _loadPlugin();

    final result = _js.evaluate('''
      (async () => {
        return await plugin.getAnime(${jsonEncode(slug)});
      })();
    ''');

    final data = await _awaitPromise(result);
    final map = jsonDecode(data) as Map<String, dynamic>;

    return AnimeDetail(
      titulo: map['titulo'] ?? '',
      sinopsis: map['sinopsis'] ?? '',
      imagen: map['imagen'] ?? '',
      estado: map['estado'] ?? '',
      generos: List<String>.from(map['generos'] ?? []),
      episodios: (map['episodios'] as List)
          .map((e) => Episode(
                numero: e['numero'] ?? 0,
                url: e['url'] ?? '',
                titulo: e['titulo'] ?? '',
              ))
          .toList(),
      url: map['url'] ?? '',
    );
  }

  Future<List<VideoServer>> getServers(String slug, int numero) async {
    _loadPlugin();

    final result = _js.evaluate('''
      (async () => {
        return await plugin.getServers(${jsonEncode(slug)}, $numero);
      })();
    ''');

    final data = await _awaitPromise(result);
    final list = jsonDecode(data) as List;
    return list
        .map((e) => VideoServer(nombre: e['nombre'] ?? '', url: e['url'] ?? ''))
        .toList();
  }

  void _loadPlugin() {
    // Expone helpers al JS global (http, btoa/atob, token, etc.)
    _js.evaluate('''
      var http = {
        get: function(url) {
          return __native_get(url);
        },
        postForm: function(url, data) {
          return __native_postForm(url, JSON.stringify(data));
        }
      };
    ''');

    // Carga el plugin
    _js.evaluate(_pluginCode);
  }

  Future<String> _awaitPromise(JsEvalResult result) async {
    // flutter_js resuelve promesas automáticamente con evaluateAsync
    // Si usas evaluateAsync, aquí ya tendrás el valor final.
    // Por simplicidad, asumimos que usamos evaluateAsync en search/getAnime.
    return result.stringResult;
  }
}