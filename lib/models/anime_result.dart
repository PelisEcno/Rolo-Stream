class AnimeResult {
  final String nombre;
  final String seo;
  final String url;
  final String imagen;
  final String estado;
  final String categoria;

  AnimeResult({
    required this.nombre,
    required this.seo,
    required this.url,
    required this.imagen,
    required this.estado,
    required this.categoria,
  });

  factory AnimeResult.fromJson(Map<String, dynamic> json) {
    return AnimeResult(
      nombre: json['nombre'] ?? '',
      seo: json['seo'] ?? '',
      url: json['url'] ?? '',
      imagen: json['imagen'] ?? '',
      estado: json['estado'] ?? '',
      categoria: json['categoria'] ?? '',
    );
  }
}