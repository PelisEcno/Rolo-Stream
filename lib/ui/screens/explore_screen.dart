import 'package:flutter/material.dart';
import 'package:latanime_plugin/latanime_plugin.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

typedef _Options = List<(String value, String label)>;

const _generos = <(String, String)>[
  ('accion', 'Acción'), ('aventura', 'Aventura'), ('carreras', 'Carreras'),
  ('ciencia-ficcion', 'Ciencia Ficción'), ('comedia', 'Comedia'), ('cyberpunk', 'Cyberpunk'),
  ('deportes', 'Deportes'), ('drama', 'Drama'), ('ecchi', 'Ecchi'), ('escolares', 'Escolares'),
  ('fantasia', 'Fantasía'), ('gore', 'Gore'), ('harem', 'Harem'), ('horror', 'Horror'),
  ('josei', 'Josei'), ('lucha', 'Lucha'), ('magia', 'Magia'), ('mecha', 'Mecha'),
  ('militar', 'Militar'), ('misterio', 'Misterio'), ('musica', 'Música'),
  ('parodias', 'Parodias'), ('psicologico', 'Psicológico'),
  ('recuerdos-de-la-vida', 'Recuerdos de la vida'), ('seinen', 'Seinen'), ('shojo', 'Shojo'),
  ('shonen', 'Shonen'), ('sobrenatural', 'Sobrenatural'), ('vampiros', 'Vampiros'),
  ('yaoi', 'Yaoi'), ('yuri', 'Yuri'), ('latino', 'Latino'), ('espacial', 'Espacial'),
  ('historico', 'Histórico'), ('samurai', 'Samurai'), ('artes-marciales', 'Artes Marciales'),
  ('demonios', 'Demonios'), ('romance', 'Romance'), ('dementia', 'Dementia'),
  ('policia', 'Policía'), ('castellano', 'Castellano'), ('historia-paralela', 'Historia paralela'),
  ('aenime', 'Aenime'), ('donghua', 'Donghua'), ('blu-ray', 'Blu-ray'),
  ('monogatari', 'Monogatari'), ('suspenso', 'Suspenso'), ('isekai', 'Isekai'),
];

final _anios = <(String, String)>[
  for (var y = 2026; y >= 1982; y--) ('$y', '$y'),
];

final _letras = <(String, String)>[
  ('09', '0-9'),
  for (final c in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z']) (c, c),
];

const _categorias = <(String, String)>[
  ('anime', 'Anime'), ('ova', 'Ova'), ('Película', 'Película'), ('especial', 'Especial'),
  ('corto', 'Corto'), ('ona', 'Ona'), ('donghua', 'Donghua'), ('sin-censura', 'Sin Censura'),
  ('preestreno', 'Preestreno'), ('pelicula-1080p', 'Película 1080p'), ('latino', 'Latino'),
  ('Película Latino', 'Película Latino'), ('castellano', 'Castellano'),
  ('Película Castellano', 'Película Castellano'), ('ova-latino', 'Ova Latino'),
  ('ova-castellano', 'Ova Castellano'), ('latino-sin-censura', 'Latino Sin Censura'),
  ('live-action', 'Live Action'), ('Cartoon', 'Cartoon'), ('catalan', 'Catalán'),
];

/// Directorio filtrable con scroll infinito. 'false' = sin filtro.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _plugin = LatanimePlugin();
  final _scroll = ScrollController();
  final _items = <FilterAnime>[];
  final _seen = <String>{};

  String _genero = 'false';
  String _fecha = 'false';
  String _letra = 'false';
  String _categoria = 'false';

  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  int _generation = 0; // descarta respuestas de filtros anteriores

  bool get _hasFilters =>
      _genero != 'false' || _fecha != 'false' || _letra != 'false' || _categoria != 'false';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) _loadNext();
    });
    _loadNext();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = await _plugin.getAnimesByFilter(
        genero: _genero,
        fecha: _fecha,
        letra: _letra,
        categoria: _categoria,
        page: _page + 1,
      );
      if (!mounted || gen != _generation) return;
      final fresh = batch.where((a) => _seen.add(a.url)).toList();
      setState(() {
        _page++;
        _items.addAll(fresh);
        if (fresh.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e.toString());
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
    if (gen != _generation) return;
    // Si la página no llena la pantalla, el scroll nunca se dispara.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent <= 0) _loadNext();
    });
  }

  /// Reinicia la lista con los filtros actuales.
  void _reset() {
    _generation++;
    setState(() {
      _items.clear();
      _seen.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _loadNext();
  }

  Future<void> _pick({
    required String title,
    required _Options options,
    required String current,
    required void Function(String) onSelected,
  }) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  for (final o in [('false', 'Todos'), ...options])
                    ListTile(
                      title: Text(o.$2,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: o.$1 == current ? AppColors.primary : null)),
                      trailing: o.$1 == current
                          ? const Icon(Icons.check_rounded, color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, o.$1),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (value == null || value == current) return;
    onSelected(value);
    _reset();
  }

  String _label(String name, String value, _Options options) {
    if (value == 'false') return name;
    return options.firstWhere((o) => o.$1 == value, orElse: () => (value, value)).$2;
  }

  Widget _chip(String name, String value, _Options options, void Function(String) set) {
    final active = value != 'false';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: active ? AppColors.primary : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _pick(title: name, options: options, current: value, onSelected: set),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Text(_label(name, value, options),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: active ? Colors.black : Colors.white)),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down_rounded,
                    size: 20, color: active ? Colors.black : AppColors.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Explorar'),
        actions: [
          IconButton(
            tooltip: 'Buscar por nombre',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              children: [
                _chip('Género', _genero, _generos, (v) => _genero = v),
                _chip('Año', _fecha, _anios, (v) => _fecha = v),
                _chip('Letra', _letra, _letras, (v) => _letra = v),
                _chip('Categoría', _categoria, _categorias, (v) => _categoria = v),
                if (_hasFilters)
                  TextButton(
                    onPressed: () {
                      _genero = _fecha = _letra = _categoria = 'false';
                      _reset();
                    },
                    child: const Text('LIMPIAR',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _results() {
    if (_items.isEmpty) {
      if (_error != null) {
        return ErrorState(title: 'No se pudo cargar', detail: _error, onRetry: _loadNext);
      }
      if (_loading || _hasMore) return const GridSkeleton();
      return const EmptyState(
        icon: Icons.filter_alt_off_rounded,
        title: 'Sin resultados',
        subtitle: 'Prueba con otra combinación de filtros.',
      );
    }
    return CustomScrollView(
      controller: _scroll,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.5,
              crossAxisSpacing: 10,
              mainAxisSpacing: 16,
            ),
            itemCount: _items.length,
            itemBuilder: (_, i) => CatalogCard(
              nombre: _items[i].titulo,
              imagen: _items[i].imagen,
              anio: _items[i].anio,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetailScreen(
                      nombre: _items[i].titulo, url: _items[i].url, imagen: _items[i].imagen),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(child: _footer()),
      ],
    );
  }

  Widget _footer() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          children: [
            const Text('No se pudo cargar más', style: TextStyle(color: AppColors.textMuted)),
            TextButton(onPressed: _loadNext, child: const Text('REINTENTAR')),
          ],
        ),
      );
    }
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 24);
  }
}
