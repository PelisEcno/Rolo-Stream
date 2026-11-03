/// Tipo de lista IPTV. Una lista de Xtream Codes se descarga igual que una M3U (su
/// `get.php?username=…&password=…&type=m3u_plus` ya devuelve M3U); el tipo solo sirve para
/// mostrarlo en la UI.
enum IPTVType { m3u, xtream }

class IPTVPlaylist {
  final String id;
  final String nombre;
  final String url;
  final IPTVType tipo;

  const IPTVPlaylist({
    required this.id,
    required this.nombre,
    required this.url,
    required this.tipo,
  });

  /// Xtream Codes: `…/get.php?username=…&password=…`. Cualquier otra URL es una M3U estática.
  static IPTVType detectType(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return IPTVType.m3u;
    final isGetPhp = uri.path.toLowerCase().endsWith('get.php');
    final hasCredentials = uri.queryParameters.containsKey('username') &&
        uri.queryParameters.containsKey('password');
    return isGetPhp && hasCredentials ? IPTVType.xtream : IPTVType.m3u;
  }

  /// Servidor de la lista, para mostrarlo sin enseñar el usuario ni la contraseña de la URL.
  String get host => Uri.tryParse(url)?.host ?? '';

  String get tipoLabel => tipo == IPTVType.xtream ? 'Xtream Codes' : 'M3U';

  Map<String, dynamic> toJson() =>
      {'id': id, 'nombre': nombre, 'url': url, 'tipo': tipo.name};

  factory IPTVPlaylist.fromJson(Map<String, dynamic> j) => IPTVPlaylist(
        id: '${j['id'] ?? ''}',
        nombre: '${j['nombre'] ?? ''}',
        url: '${j['url'] ?? ''}',
        tipo: IPTVType.values.firstWhere((t) => t.name == j['tipo'], orElse: () => IPTVType.m3u),
      );
}

/// Un canal de una lista M3U.
class Channel {
  final String nombre;
  final String? logo;

  /// `tvg-id`: identificador del canal en la guía de programación (XMLTV).
  final String? tvgId;
  final String grupo;
  final String url;

  /// Cabeceras pedidas por la propia lista (`#EXTVLCOPT:http-user-agent=…`, `http-referrer=…`).
  final Map<String, String> headers;

  const Channel({
    required this.nombre,
    required this.url,
    this.logo,
    this.tvgId,
    this.grupo = Channel.sinGrupo,
    this.headers = const {},
  });

  static const sinGrupo = 'Sin grupo';
}
