/// Las fuentes con temporadas (Cuevana) codifican `numero = temporada * 10000 + episodio`.
/// Ninguna fuente de anime se acerca a 10000 episodios, así que los números menores
/// son episodios corridos normales.
const _seasonFactor = 10000;

/// "E4" o, para series con temporadas, "T2 E4".
String episodeLabel(int numero) =>
    numero >= _seasonFactor ? 'T${numero ~/ _seasonFactor} E${numero % _seasonFactor}' : 'E$numero';

/// "Episodio 4" o "Temporada 2 · Episodio 4".
String episodeName(int numero) => numero >= _seasonFactor
    ? 'Temporada ${numero ~/ _seasonFactor} · Episodio ${numero % _seasonFactor}'
    : 'Episodio $numero';
