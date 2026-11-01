class VideoServer {
  final String nombre;
  final String url; // URL del embed ya decodificada (Filemoon, Doodstream, etc.)

  VideoServer({
    required this.nombre,
    required this.url,
  });
}