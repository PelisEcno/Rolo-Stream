import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

class HttpClientService {
  static const String _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36';

  late final Dio _dio;
  late final CookieJar _cookieJar;

  HttpClientService._();
  static final HttpClientService instance = HttpClientService._();

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    final cookiePath = '${dir.path}/rolostream_cookies/';
    _cookieJar = PersistCookieJar(
      storage: FileStorage(cookiePath),
      ignoreExpires: false,
    );

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

  Dio get dio => _dio;

  /// Hace un GET y devuelve el HTML como String.
  Future<String> get(String url, {Map<String, String>? headers}) async {
    final res = await _dio.get<String>(
      url,
      options: Options(
        responseType: ResponseType.plain,
        headers: headers,
      ),
    );
    return res.data ?? '';
  }

  /// Hace un POST form-urlencoded y devuelve el JSON decodificado.
  Future<dynamic> postForm(
    String url,
    Map<String, String> data, {
    Map<String, String>? headers,
  }) async {
    final res = await _dio.post(
      url,
      data: data,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        headers: {
          'Accept': 'application/json, text/javascript, */*; q=0.01',
          'X-Requested-With': 'XMLHttpRequest',
          ...?headers,
        },
        responseType: ResponseType.json,
      ),
    );
    return res.data;
  }
}