import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import '../models/anime_result.dart';
import '../models/anime_detail.dart';
import '../models/video_server.dart';
import '../services/http_client.dart';

class PluginRuntime {
  final JavascriptRuntime _js;
  final String _pluginCode;

  PluginRuntime(this._pluginCode) : _js = getJavascriptRuntime() {
    _setupBridge();
  }

  /// Expone funciones nativas de Dart al JS global.
  void _setupBridge() {
    _js.onMessage('__native_get', (dynamic args) async {
      final url = args.toString();
      try {
        final html = await HttpClientService.instance.get(url);
        return html;
      } catch (e) {
        return 'ERROR: $e';
      }
    });

    _js.onMessage('__native_postForm', (dynamic args) async {
      try {
        final data = jsonDecode(args.toString()) as Map<String, dynamic>;
        final url = data['url'] as String;
        final body = Map<String, String>.from(data['body'] as Map);
        final res = await HttpClientService.instance.postForm(url, body);
        return jsonEncode(res);
      } catch (e) {
        return 'ERROR: $e';
      }
    });
  }

  /// Helpers JS: http.get y http.postForm envuelven los callbacks nativos.
  void _injectHelpers() {
    _js.evaluate('''
      var __pending = {};
      var __id = 0;

      function __callNative(name, args) {
        return new Promise((resolve) => {
          var id = '__cb_' + (++__id);
          __pending[id] = resolve;
          sendMessage(name + ':' + id + ':' + JSON.stringify(args));
        });
      }

      var http = {
        get: function(url) {
          return __callNative('__native_get', url);
        },
        postForm: function(url, body) {
          return __callNative('__native_postForm', JSON.stringify({url: url, body: body}));
        }
      };

      function __resolve(id, value) {
        if (__pending[id]) {
          __pending[id](value);
          delete __pending[id];
        }
      }

      // atob / btoa (no vienen en QuickJS por defecto)
      function atob(str) {
        return decodeURIComponent(escape(
          String.fromCharCode.apply(null,
            str.split('').map(function(c) { return c.charCodeAt(0); })
          )
        ));
      }
      function btoa(str) {
        return btoa_raw(str);
      }
    ''');
  }

  Future<void> _ensureLoaded() async {
    _injectHelpers();
    _js.evaluate(_pluginCode);
  }

  Future<List<AnimeResult>> search(String query) async {
    await _ensureLoaded();
    final result = await _js.evaluateAsync('''
      (async () => {
        return JSON.stringify(await plugin.search(${jsonEncode(query)}));
      })();
    ''');
    final data = jsonDecode(result.stringResult) as List;
    return data.map((e) => AnimeResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<AnimeDetail> getAnime(String slug) async {
    await _ensureLoaded();
    final result = await _js.evaluateAsync('''
      (async () => {
        return JSON.stringify(await plugin.getAnime(${jsonEncode(slug)}));
      })();
    ''');
    final map = jsonDecode(result.stringResult) as Map<String, dynamic>;
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
    await _ensureLoaded();
    final result = await _js.evaluateAsync('''
      (async () => {
        return JSON.stringify(await plugin.getServers(${jsonEncode(slug)}, $numero));
      })();
    ''');
    final data = jsonDecode(result.stringResult) as List;
    return data
        .map((e) => VideoServer(
              nombre: e['nombre'] ?? '',
              url: e['url'] ?? '',
            ))
        .toList();
  }
}