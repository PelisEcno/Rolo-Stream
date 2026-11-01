import 'package:flutter/material.dart';
import 'package:rolostream_core/rolostream_core.dart';
import '../../services/source_registry.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';
import 'search_screen.dart';

typedef _Options = List<FilterOption>;

/// Directorio filtrable con scroll infinito. 'false' = sin filtro.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final SourcePlugin _source = pluginRegistry.active;
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
      final batch = await _source.getAnimesByFilter(
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
                  for (final o in [const FilterOption('false', 'Todos'), ...options])
                    ListTile(
                      title: Text(o.label,
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: o.value == current ? AppColors.primary : null)),
                      trailing: o.value == current
                          ? const Icon(Icons.check_rounded, color: AppColors.primary)
                          : null,
                      onTap: () => Navigator.pop(ctx, o.value),
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
    return options
        .firstWhere((o) => o.value == value, orElse: () => FilterOption(value, value))
        .label;
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
    final opts = _source.filterOptions;
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
                // Cada fuente ofrece sus propias opciones; una lista vacía oculta el filtro.
                if (opts.generos.isNotEmpty)
                  _chip('Género', _genero, opts.generos, (v) => _genero = v),
                if (opts.anios.isNotEmpty)
                  _chip('Año', _fecha, opts.anios, (v) => _fecha = v),
                if (opts.letras.isNotEmpty)
                  _chip('Letra', _letra, opts.letras, (v) => _letra = v),
                if (opts.categorias.isNotEmpty)
                  _chip('Categoría', _categoria, opts.categorias, (v) => _categoria = v),
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
                  builder: (_) => DetailScreen(sourceId: _source.id, 
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
