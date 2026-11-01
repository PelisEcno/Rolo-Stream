import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:html/parser.dart' as html_parser;

class TestHttpClient {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';

  late final Dio _dio;
  late final CookieJar _cookieJar;

  TestHttpClient() {
    _cookieJar = CookieJar();
    _dio = Dio(BaseOptions(
      headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
      },
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<String> get(String url) async {
    final res = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    return res.data ?? '';
  }

  Future<dynamic> postForm(String url, Map<String, String> data) async {
    final res = await _dio.post(
      url,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
        },
        responseType: ResponseType.json,
      ),
    );
    return res.data;
  }
}

class TestPluginRuntime {
  final TestHttpClient http = TestHttpClient();
  String? cachedToken;

  Future<String> getToken() async {
    if (cachedToken != null) return cachedToken!;
    final html = await http.get('https://latanime.org/');
    final match = RegExp(r'name="csrf-token" content="([^"]+)"').firstMatch(html);
    if (match == null) throw Exception('No se encontró el token CSRF');
    cachedToken = match.group(1);
    print('✅ Token obtenido: ${cachedToken!.substring(0, 10)}...');
    return cachedToken!;
  }

  Future<void> testSearch(String query) async {
    print('\n--- 🔍 Iniciando búsqueda: $query ---');
    final token = await getToken();
    
    print('Enviando POST a /buscar_ajax...');
    final res = await http.postForm('https://latanime.org/buscar_ajax', {
      '_token': token,
      'q': query,
    });

    // Latanime devuelve a veces un String que contiene un JSON
    final dynamic parsedRes = res is String ? jsonDecode(res) : res;

    if (parsedRes is List) {
      print('✅ ¡Búsqueda exitosa! Se encontraron ${parsedRes.length} resultados:');
      for (var anime in parsedRes) {
        print('- ${anime['nombre']} (${anime['url']})');
      }
    } else {
      print('❌ Error: La respuesta no es una lista.');
      print(res);
    }
  }

  Future<void> testAnimeDetail() async {
    print('\n--- 📖 Probando detalle del anime ---');
    final slug = 'naruto-latino';
    final url = 'https://latanime.org/anime/$slug';
    
    print('Obteniendo HTML de $url...');
    final html = await http.get(url);

    // Usamos el paquete html para parsear el DOM de forma limpia
    final document = html_parser.parse(html);

    final titulo = document.querySelector('h2')?.text.trim() ?? 'Desconocido';
    final sinopsis = document.querySelector('p.my-2.opacity-75')?.text.trim() ?? 'Sin sinopsis';
    final imagen = document.querySelector('img.img-fluid2')?.attributes['src'] ?? 'Sin imagen';
    final estado = document.querySelector('.btn-estado')?.text.trim() ?? 'Desconocido';

    // Extraer géneros
    final generos = document
        .querySelectorAll('a[href^="/genero/"]')
        .map((e) => e.text.trim())
        .toList();

    // Extraer capítulos
    final episodios = <Map<String, dynamic>>[];
    final enlaces = document.querySelectorAll('a[href*="/ver/"]');
    for (var link in enlaces) {
      final href = link.attributes['href'] ?? '';
      final img = link.querySelector('img');
      final alt = img?.attributes['alt'] ?? '';
      
      // El alt suele ser "Naruto Latino capitulo 1"
      final matchNum = RegExp(r'capitulo (\d+)', caseSensitive: false).firstMatch(alt);
      if (matchNum != null) {
        episodios.add({
          'numero': int.parse(matchNum.group(1)!),
          'url': href,
          'titulo': alt,
        });
      }
    }

    // Ordenar por número
    episodios.sort((a, b) => (a['numero'] as int).compareTo(b['numero'] as int));

    print('✅ Detalle extraído:');
    print('   Título: $titulo');
    print('   Estado: $estado');
    print('   Imagen: $imagen');
    print('   Géneros: ${generos.join(", ")}');
    print('   Sinopsis: ${sinopsis.substring(0, 50)}...');
    print('   Capítulos encontrados: ${episodios.length}');
    if (episodios.isNotEmpty) {
      print('   Primer cap: ${episodios.first['titulo']} (${episodios.first['url']})');
      print('   Último cap: ${episodios.last['titulo']} (${episodios.last['url']})');
    }
  }

  Future<void> testServers() async {
    print('\n--- 📺 Probando extracción de servidores ---');
    final slug = 'naruto-latino';
    final episode = 1;
    final url = 'https://latanime.org/ver/$slug-episodio-$episode';
    
    print('Obteniendo HTML de $url...');
    final html = await http.get(url);

    print('Extrayendo data-player (Base64)...');
    final regex = RegExp(r'data-player="([^"]+)"[^>]*>([^<]+)<\/a>');
    final matches = regex.allMatches(html);

    if (matches.isEmpty) {
      print('❌ No se encontraron servidores.');
      return;
    }

    print('✅ Servidores encontrados:');
    for (var match in matches) {
      final base64Str = match.group(1)!;
      final nombre = match.group(2)!.trim();
      
      try {
        final decodedUrl = utf8.decode(base64Decode(base64Str));
        print('- $nombre: $decodedUrl');
      } catch (e) {
        print('- $nombre: (Error al decodificar) $base64Str');
      }
    }
  }
}

void main() async {
  final runtime = TestPluginRuntime();
  
  try {
    // Prueba 1: Búsqueda
    await runtime.testSearch('naruto');
    
    // Prueba 2: Detalle del anime
    await runtime.testAnimeDetail();
    
    // Prueba 3: Servidores del episodio
    await runtime.testServers();
    
    print('\n🎉 Todas las pruebas finalizadas.');
  } catch (e, stack) {
    print('\n❌ ERROR CRÍTICO:');
    print(e);
    print(stack);
  }
}