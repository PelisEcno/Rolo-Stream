import 'package:flutter/material.dart';
import 'package:rolostream_core/rolostream_core.dart';
import '../../services/source_registry.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';

/// Animes en emisión con paginación infinita.
class AiringScreen extends StatefulWidget {
  const AiringScreen({super.key});

  @override
  State<AiringScreen> createState() => _AiringScreenState();
}

class _AiringScreenState extends State<AiringScreen> {
  final SourcePlugin _source = pluginRegistry.active;
  final _scroll = ScrollController();
  final _items = <AiringAnime>[];
  final _seen = <String>{};

  int _page = 0;
  bool _loading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadNext();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final batch = await _source.getAiringAnimes(page: _page + 1);
      if (!mounted) return;
      // Si el sitio repite la última página, no habrá elementos nuevos.
      final fresh = batch.where((a) => _seen.add(a.url)).toList();
      setState(() {
        _page++;
        _items.addAll(fresh);
        if (fresh.isEmpty) _hasMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // Si la primera página no llena la pantalla, el scroll nunca se dispara.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients && _scroll.position.maxScrollExtent <= 0) _loadNext();
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _seen.clear();
      _page = 0;
      _hasMore = true;
      _error = null;
    });
    await _loadNext();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Emisión')),
      body: _body(),
    );
  }

  Widget _body() {
    if (_items.isEmpty) {
      if (_error != null) {
        return ErrorState(error: _error, onRetry: _loadNext);
      }
      if (_loading) return const GridSkeleton();
      return const EmptyState(
        icon: Icons.live_tv_rounded,
        title: 'Nada en emisión',
        subtitle: 'Vuelve a intentarlo más tarde.',
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _refresh,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _items.length,
              itemBuilder: (_, i) => CatalogCard(
                nombre: _items[i].titulo,
                imagen: _items[i].imagen,
                tipo: _items[i].tipo,
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
      ),
    );
  }

  Widget _footer() {
    if (_error != null) return ErrorState(error: _error, onRetry: _loadNext);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 24);
  }
}
