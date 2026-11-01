const BASE = 'https://latanime.org';
let cachedToken = null;

async function getToken() {
  if (cachedToken) return cachedToken;
  const html = await http.get(BASE + '/');
  const match = html.match(/name="csrf-token" content="([^"]+)"/);
  if (!match) throw new Error('No se pudo obtener el token CSRF');
  cachedToken = match[1];
  return cachedToken;
}

const plugin = {
  name: 'Latanime',
  version: '1.0.0',

  async search(query) {
    if (query.length < 3) return [];
    const token = await getToken();
    const raw = await http.postForm(BASE + '/buscar_ajax', {
      _token: token,
      q: query,
    });
    const res = JSON.parse(raw);
    return res.map(item => ({
      nombre: item.nombre,
      seo: item.seo,
      url: item.url,
      imagen: item.imagen,
      estado: item.estado,
      categoria: item.categoria,
    }));
  },

  async getAnime(slug) {
    const html = await http.get(`${BASE}/anime/${slug}`);
    const titulo = (html.match(/<h2>([^<]+)<\/h2>/) || [])[1] || '';
    const sinopsis = (html.match(/<p class="my-2 opacity-75">([\s\S]*?)<\/p>/) || [])[1] || '';
    const imagen = (html.match(/<img[^>]+class="img-fluid2"[^>]+src="([^"]+)"/) || [])[1] || '';
    const estado = (html.match(/btn-estado (\w+)/) || [])[1] || '';

    const generos = [];
    const genRegex = /<a href="[^"]+\/genero\/[^"]+"><div class="btn">([^<]+)<\/div><\/a>/g;
    let m;
    while ((m = genRegex.exec(html)) !== null) generos.push(m[1].trim());

    const episodios = [];
    const epRegex = /<a href="([^"]+\/ver\/[^"]+)">[\s\S]*?alt="[^"]*capitulo (\d+)"/g;
    while ((m = epRegex.exec(html)) !== null) {
      episodios.push({
        numero: parseInt(m[2], 10),
        url: m[1],
        titulo: 'Capítulo ' + m[2],
      });
    }

    return { titulo, sinopsis, imagen, estado, generos, episodios, url: `${BASE}/anime/${slug}` };
  },

  async getServers(slug, numero) {
    const html = await http.get(`${BASE}/ver/${slug}-episodio-${numero}`);
    const servers = [];
    const regex = /data-player="([^"]+)"[^>]*>([^<]+)<\/a>/g;
    let m;
    while ((m = regex.exec(html)) !== null) {
      let url = '';
      try { url = atob(m[1]); } catch (e) { url = m[1]; }
      servers.push({ nombre: m[2].trim(), url });
    }
    return servers;
  },
};