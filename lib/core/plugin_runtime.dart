import 'dart:convert';
import 'package:flutter_js/flutter_js.dart';
import '../models/anime_result.dart';
import '../models/anime_detail.dart';
import '../models/video_server.dart';
import '../services/http_client.dart';

class PluginRuntime {
  final JavascriptRuntime _js;
  final String _pluginCode;
  bool _isBridgeSetup = false;

  PluginRuntime(this._pluginCode) : _js = getJavascriptRuntime() {
    _setupBridge();
  }

  void _setupBridge() {
    if (_isBridgeSetup) return;

    // 1. Escuchar llamadas desde JS a Dart
    _js.onMessage('native_get', (args) async {
      final url = args[0].toString();
      try {
        final res = await HttpClientService.instance.get(url);
        return res;
      } catch (e) {
        return 'ERROR_GET: $e';
      }
    });

    _js.onMessage('native_postForm', (args) async {
      final url = args[0].toString();
      try {
        final Map<String, dynamic> body = jsonDecode(args[1].toString());
        final res = await HttpClientService.instance.postForm(
          url,
          body.map((key, value) => MapEntry(key, value.toString())),
        );
        return jsonEncode(res); // Devolvemos string JSON a JS
      } catch (e) {
        return 'ERROR_POST: $e';
      }
    });

    _isBridgeSetup = true;
  }

  void _loadPlugin() {
        _js.evaluate(r'''
      // Helpers para que JS pueda llamar a Dart
      var http = {
        get: function(url) {
          var result = sendMessage('native_get', [url]);
          return result;
        },
        postForm: function(url, data) {
          var result = sendMessage('native_postForm', [url, JSON.stringify(data)]);
          return result;
        }
      };

      // Polyfill de atob para QuickJS
      if (typeof atob === 'undefined') {
        var atob = function(input) {
          var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
          var str = String(input).replace(/=+$/, '');
          if (str.length % 4 == 1) { throw new Error("'atob' failed"); }
          var output = '';
          for (var bc = 0, bs, buffer, idx = 0; buffer = str.charAt(idx++); ~buffer && (bs = bc % 4 ? bs * 64 + buffer : buffer, bc++ % 4) ? output += String.fromCharCode(255 & bs >> (-2 * bc & 6)) : 0) {
            buffer = chars.indexOf(buffer);
          }
          return output;
        };
      }
    ''');

    _js.evaluate(_pluginCode);
  }

  Future<List<AnimeResult>> search(String query) async {
    _loadPlugin();
    final result = await _js.evaluateAsync('''
      (async () => {
        return JSON.stringify(await plugin.search(${jsonEncode(query)}));
      })();
    ''');
    
    final resolved = await _js.handlePromise(result);
    final data = jsonDecode(resolved.stringResult) as List;
    return data.map((e) => AnimeResult.fromJson(e)).toList();
  }

  Future<AnimeDetail> getAnime(String slug) async {
    _loadPlugin();
    final result = await _js.evaluateAsync('''
      (async () => {
        return JSON.stringify(await plugin.getAnime(${jsonEncode(slug)}));
      })();
    ''');

    final resolved = await _js.handlePromise(result);
    final map = jsonDecode(resolved.stringResult) as Map<String, dynamic>;

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
    final result = await _js.evaluateAsync('''
      (async () => {
        return JSON.stringify(await plugin.getServers(${jsonEncode(slug)}, $numero));
      })();
    ''');

    final resolved = await _js.handlePromise(result);
    final data = jsonDecode(resolved.stringResult) as List;
    return data
        .map((e) => VideoServer(nombre: e['nombre'] ?? '', url: e['url'] ?? ''))
        .toList();
  }
}