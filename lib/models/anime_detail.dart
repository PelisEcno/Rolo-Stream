class AnimeDetail {
  final String titulo;
  final String sinopsis;
  final String imagen;
  final String estado;
  final List<String> generos;
  final List<Episode> episodios;
  final String url;

  AnimeDetail({
    required this.titulo,
    required this.sinopsis,
    required this.imagen,
    required this.estado,
    required this.generos,
    required this.episodios,
    required this.url,
  });
}

class Episode {
  final int numero;
  final String url;
  final String titulo;

  Episode({
    required this.numero,
    required this.url,
    required this.titulo,
  });
}