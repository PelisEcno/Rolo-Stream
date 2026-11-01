import 'dart:convert';
import 'package:dio/dio.dart';

void main() async {
  // El ID del video de prueba (Rilakkuma 29)
  const String videoId = 'b6v7uku7pxli';
  const String embedUrl = 'https://hexload.com/embed-$videoId';

  final dio = Dio(BaseOptions(
    headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Referer': embedUrl,
      'Origin': 'https://hexload.com',
    },
    validateStatus: (status) => status != null && status < 500,
  ));

  print('--- 🕵️‍♂️ Iniciando test de Hexload ---');
  print('ID: $videoId');
  print('Embed: $embedUrl');
  print('');

  try {
    // PASO 1: POST a /download
    print('1. Haciendo POST a https://hexload.com/download ...');
    final response = await dio.post(
      'https://hexload.com/download',
      data: {
        'op': 'download3',
        'id': videoId,
        'ajax': '1',
        'method_free': '1',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );

    print('   Status: ${response.statusCode}');
    
    // La respuesta puede venir como String o como Map. La manejamos.
    dynamic data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }

    if (data is! Map) {
      print('   ❌ Respuesta no es JSON válido: $data');
      return;
    }

    if (data['msg'] != 'OK') {
      print('   ❌ El servidor respondió con error: ${data['msg']}');
      print('   Respuesta completa: $data');
      return;
    }

    final String rawUrl = data['result']['url'];
    print('   ✅ URL parcial obtenida: $rawUrl');

    // PASO 2: Convertir a Base64
    print('2. Convirtiendo URL a Base64...');
    final String base64Url = base64Encode(utf8.encode(rawUrl));
    print('   ✅ Base64: ${base64Url.substring(0, 50)}...');

    // PASO 3: Construir URL final y probarla
    print('3. Construyendo URL final y probando...');
    final String finalUrl = 'https://hexload.com/cgi-bin/test.pl?op=$base64Url';
    print('   URL final: $finalUrl');

    // Hacemos un GET (con redirect deshabilitado) para ver a dónde redirige
    final finalResponse = await dio.get(
      finalUrl,
      options: Options(
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400, // Permitir 3xx
      ),
    );

    print('   Status: ${finalResponse.statusCode}');
    if (finalResponse.statusCode == 302 || finalResponse.statusCode == 301) {
      final redirectUrl = finalResponse.headers.value('location');
      print('   ✅ Redirige a: $redirectUrl');
    } else if (finalResponse.statusCode == 200) {
      final contentType = finalResponse.headers.value('content-type');
      print('   ✅ Status 200. Content-Type: $contentType');
      print('   (Si es video/mp4, el enlace es directo)');
    } else {
      print('   ⚠️ Status inesperado: ${finalResponse.statusCode}');
    }

    print('');
    print('--- 🎉 Test finalizado ---');
  } catch (e, stack) {
    print('❌ ERROR CRÍTICO:');
    print(e);
    print(stack);
  }
}