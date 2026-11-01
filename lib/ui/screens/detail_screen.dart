import 'package:flutter/material.dart';
import 'package:rolostream_core/rolostream_core.dart';
import '../../services/favorites_service.dart';
import '../../services/source_registry.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final String nombre;
  final String url;
  final String imagen;

  /// Fuente de la que viene la serie; si es null se usa la activa.
  final String? sourceId;

  const DetailScreen({
    super.key,
    required this.nombre,
    required this.url,
    required this.imagen,
    this.sourceId,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final SourcePlugin _source =
      pluginRegistry.byId(widget.sourceId ?? '') ?? pluginRegistry.active;
  late Future<AnimeDetail> _future;
  bool _descending = false;
  bool _expanded = false;

  late final String _slug = _source.slugFromUrl(widget.url);

  @override
  void initState() {
    super.initState();
    _future = _source.getAnime(_slug);
  }

  void _retry() => setState(() => _future = _source.getAnime(_slug));

  void _play(Episode ep) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
            sourceId: _source.id,
            slug: _slug,
            numero: ep.numero,
            animeTitulo: widget.nombre),
      ),
    );
  }

  Widget _hero(String imagen, String titulo) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 380,
      backgroundColor: AppColors.background,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            PosterImage(url: imagen),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x80000000), Colors.transparent, AppColors.background],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actions(AnimeDetail d, String titulo, String imagen) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: d.episodios.isEmpty ? null : () => _play(d.episodios.first),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(d.episodios.isEmpty
                ? 'SIN EPISODIOS'
                : 'COMENZAR A VER E${d.episodios.first.numero}'),
          ),
        ),
        const SizedBox(width: 12),
        ListenableBuilder(
          listenable: FavoritesService.instance,
          builder: (_, __) {
            final fav = FavoritesService.instance.isFavorite(widget.url);
            return OutlinedButton(
              onPressed: () => FavoritesService.instance
                  .toggle(FavoriteAnime(
                  nombre: titulo, url: widget.url, imagen: imagen, sourceId: _source.id)),
              child: Icon(fav ? Icons.bookmark_rounded : Icons.bookmark_add_outlined),
            );
          },
        ),
      ],
    );
  }

  Widget _episodeTile(Episode ep, String imagen) {
    return InkWell(
      onTap: () => _play(ep),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 136,
                height: 77,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: imagen),
                    Container(color: Colors.black38),
                    const Center(
                        child: Icon(Icons.play_circle_outline_rounded,
                            size: 34, color: Colors.white)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('E${ep.numero}',
                      style: const TextStyle(
                          color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text('Episodio ${ep.numero}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<AnimeDetail>(
        future: _future,
        builder: (context, snap) {
          final d = snap.data;
          final imagen = (d?.imagen.isNotEmpty ?? false) ? d!.imagen : widget.imagen;
          final titulo = (d?.titulo.isNotEmpty ?? false) ? d!.titulo : widget.nombre;
          final meta = [
            if (d != null && d.estado.isNotEmpty) d.estado,
            if (d != null) ...d.generos,
          ].join('  •  ').toUpperCase();

          return CustomScrollView(
            slivers: [
              _hero(imagen, titulo),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo,
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(meta,
                            style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4)),
                      ],
                      if (d != null) ...[
                        const SizedBox(height: 16),
                        _actions(d, titulo, imagen),
                        if (d.sinopsis.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: () => setState(() => _expanded = !_expanded),
                            child: Text(
                              d.sinopsis,
                              maxLines: _expanded ? null : 4,
                              overflow: _expanded ? null : TextOverflow.ellipsis,
                              style: const TextStyle(color: Color(0xFFD0D0D0), height: 1.5),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() => _expanded = !_expanded),
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              child: Text(_expanded ? 'MOSTRAR MENOS' : 'MOSTRAR MÁS',
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w800)),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text('EPISODIOS (${d.episodios.length})',
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6)),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Invertir orden',
                              icon: const Icon(Icons.swap_vert_rounded),
                              onPressed: () => setState(() => _descending = !_descending),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (snap.connectionState != ConnectionState.done)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (snap.hasError)
                SliverToBoxAdapter(
                  child: ErrorState(
                      title: 'No se pudo cargar la serie',
                      detail: snap.error.toString(),
                      onRetry: _retry),
                )
              else if (d != null)
                SliverPadding(
                  padding: const EdgeInsets.only(bottom: 32),
                  sliver: SliverList.builder(
                    itemCount: d.episodios.length,
                    itemBuilder: (_, i) => _episodeTile(
                        _descending ? d.episodios[d.episodios.length - 1 - i] : d.episodios[i],
                        imagen),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
