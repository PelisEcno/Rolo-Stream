import 'package:flutter/material.dart';
import 'package:rolostream_core/rolostream_core.dart';
import '../../services/source_registry.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final SourcePlugin _source = pluginRegistry.active;

  List<AnimeResult> _results = [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < 3) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Escribe al menos 3 letras')));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });
    try {
      final results = await _source.search(q);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searched = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _body() {
    if (_loading) return const GridSkeleton();
    if (_error != null) {
      return ErrorState(title: 'No se pudo buscar', detail: _error, onRetry: _search);
    }
    if (!_searched) {
      return const EmptyState(
        icon: Icons.travel_explore_rounded,
        title: 'Encuentra tu próximo anime',
        subtitle: 'Busca por título para empezar a ver.',
      );
    }
    if (_results.isEmpty) {
      return const EmptyState(
        icon: Icons.sentiment_dissatisfied_rounded,
        title: 'Sin resultados',
        subtitle: 'Prueba con otro título.',
      );
    }
    return AnimeGrid(
      count: _results.length,
      builder: (i) {
        final a = _results[i];
        return AnimeCard(
          nombre: a.nombre,
          imagen: a.imagen,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => DetailScreen(sourceId: _source.id, nombre: a.nombre, url: a.url, imagen: a.imagen)),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                  onPressed: () => _controller.clear(),
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(child: _body()),
        ],
      ),
    );
  }
}
