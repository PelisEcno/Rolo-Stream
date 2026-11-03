import 'package:flutter/material.dart';
import 'package:rolostream_core/rolostream_core.dart';
import '../../services/source_registry.dart';
import '../../services/watch_progress_service.dart';
import '../theme/app_theme.dart';
import '../utils/episode_label.dart';
import '../widgets/anime_card.dart';
import '../widgets/source_picker.dart';
import 'detail_screen.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SourcePlugin _source = pluginRegistry.active;

  late Future<List<RecentSerie>> _seriesFuture;
  late Future<List<RecentEpisode>> _episodesFuture;

  @override
  void initState() {
    super.initState();
    _seriesFuture = _source.getRecentSeries();
    _episodesFuture = _source.getLatestEpisodes();
  }

  void _reloadSeries() => setState(() => _seriesFuture = _source.getRecentSeries());
  void _reloadEpisodes() => setState(() => _episodesFuture = _source.getLatestEpisodes());

  Future<void> _refresh() async {
    setState(() {
      _seriesFuture = _source.getRecentSeries();
      _episodesFuture = _source.getLatestEpisodes();
    });
    try {
      await Future.wait<Object?>([_seriesFuture, _episodesFuture]);
    } catch (_) {
      // Cada sección muestra su propio error.
    }
  }

  void _openSerie(RecentSerie s) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => DetailScreen(sourceId: _source.id, nombre: s.titulo, url: s.url, imagen: s.imagen)),
      );

  void _openEpisode(RecentEpisode ep) {
    final parsed = _source.parseEpisodeUrl(ep.url);
    if (parsed == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo abrir el episodio')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
            sourceId: _source.id,
            slug: parsed.slug,
            numero: parsed.numero,
            animeTitulo: ep.titulo,
            imagen: ep.imagen),
      ),
    );
  }

  void _resume(WatchProgress p) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlayerScreen(
              sourceId: p.sourceId,
              slug: p.slug,
              numero: p.numero,
              animeTitulo: p.titulo,
              imagen: p.imagen),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: const [SourceButton(), SizedBox(width: 4)],
        title: const Text.rich(
          TextSpan(children: [
            TextSpan(text: 'ROLO', style: TextStyle(color: AppColors.primary)),
            TextSpan(text: 'STREAM'),
          ]),
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.2),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        edgeOffset: 80,
        onRefresh: _refresh,
        // Un solo scrollable con slivers (la cuadrícula ya no es un GridView anidado con
        // shrinkWrap). Sin rebote: con el banner detrás de la barra, el rebote de iOS
        // dejaba ver el fondo vacío encima. AlwaysScrollable mantiene el pull-to-refresh.
        child: CustomScrollView(
          physics: const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverToBoxAdapter(
              child: _HeroSection(
                  future: _seriesFuture, onOpen: _openSerie, onRetry: _reloadSeries),
            ),
            SliverToBoxAdapter(child: _ContinueWatchingSection(onOpen: _resume)),
            SliverToBoxAdapter(
              child: _RecentEpisodesSection(
                  future: _episodesFuture,
                  source: _source,
                  onOpen: _openEpisode,
                  onRetry: _reloadEpisodes),
            ),
            _RecentSeriesSection(
                future: _seriesFuture, onOpen: _openSerie, onRetry: _reloadSeries),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
}

// ───────────────────────── 1. Hero ─────────────────────────

class _HeroSection extends StatelessWidget {
  final Future<List<RecentSerie>> future;
  final void Function(RecentSerie) onOpen;
  final VoidCallback onRetry;
  const _HeroSection({required this.future, required this.onOpen, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecentSerie>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 460,
            color: AppColors.surface,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }
        if (snap.hasError) {
          return SizedBox(
            height: 320,
            child: ErrorState(error: snap.error, onRetry: onRetry),
          );
        }
        final series = snap.data ?? const <RecentSerie>[];
        if (series.isEmpty) return const SizedBox(height: 96);
        final s = series.first;
        return SizedBox(
          height: 460,
          child: Stack(
            fit: StackFit.expand,
            children: [
              PosterImage(url: s.imagen),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xB3000000),
                      Colors.transparent,
                      Color(0x990A0A0A),
                      AppColors.background,
                    ],
                    stops: [0, 0.3, 0.75, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Column(
                  children: [
                    Text(s.titulo,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 26, fontWeight: FontWeight.w900, height: 1.1)),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => onOpen(s),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: const Text('VER AHORA'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────── Seguir viendo ───────────────────────

class _ContinueWatchingSection extends StatelessWidget {
  final void Function(WatchProgress) onOpen;
  const _ContinueWatchingSection({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: WatchProgressService.instance,
      builder: (context, _) {
        final items = [
          for (final p in WatchProgressService.instance.continueWatching())
            // Una fuente que ya no existe no se puede reproducir.
            if (pluginRegistry.byId(p.sourceId) != null) p,
        ];
        if (items.isEmpty) return const SizedBox.shrink();
        return SectionRow(
          title: 'Seguir viendo',
          count: items.length,
          itemWidth: 208,
          height: 117,
          builder: (i) => _ContinueCard(progress: items[i], onTap: () => onOpen(items[i])),
        );
      },
    );
  }
}

class _ContinueCard extends StatelessWidget {
  final WatchProgress progress;
  final VoidCallback onTap;
  const _ContinueCard({required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _WideCard(
      imagen: progress.imagen,
      etiqueta: episodeLabel(progress.numero),
      titulo: progress.titulo,
      onTap: onTap,
      progreso: progress.fraction,
    );
  }
}

/// Tarjeta 16:9 con el texto sobre el degradado.
class _WideCard extends StatelessWidget {
  final String imagen;
  final String? etiqueta;
  final String titulo;
  final String fecha;
  final double? progreso;
  final VoidCallback onTap;
  const _WideCard({
    required this.imagen,
    required this.titulo,
    required this.onTap,
    this.etiqueta,
    this.fecha = '',
    this.progreso,
  });

  @override
  Widget build(BuildContext context) {
    return PressScale(
      onTap: onTap,
      child: RoundedPoster(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ParallaxImage(url: imagen),
            const PosterScrim(),
            if (fecha.isNotEmpty)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  color: Colors.black87,
                  child: Text(fecha,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: progreso == null ? 7 : 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (etiqueta != null)
                    Text(etiqueta!,
                        style: const TextStyle(
                            color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800)),
                  Text(titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            if (progreso != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(
                  value: progreso,
                  minHeight: 3,
                  color: AppColors.primary,
                  backgroundColor: Colors.white24,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────── 2. Añadidos recientemente ───────────────────

class _RecentEpisodesSection extends StatelessWidget {
  final Future<List<RecentEpisode>> future;
  final SourcePlugin source;
  final void Function(RecentEpisode) onOpen;
  final VoidCallback onRetry;
  const _RecentEpisodesSection(
      {required this.future,
      required this.source,
      required this.onOpen,
      required this.onRetry});

  static const _itemWidth = 208.0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecentEpisode>>(
      future: future,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        if (done && snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('Añadidos recientemente'),
              ErrorState(error: snap.error, onRetry: onRetry),
            ],
          );
        }
        final eps = snap.data ?? const <RecentEpisode>[];
        if (done && eps.isEmpty) return const SizedBox.shrink();
        return SectionRow(
          title: 'Añadidos recientemente',
          count: eps.length,
          loading: !done,
          itemWidth: _itemWidth,
          height: 117,
          builder: (i) => _EpisodeCard(
            ep: eps[i],
            numero: source.parseEpisodeUrl(eps[i].url)?.numero,
            onTap: () => onOpen(eps[i]),
          ),
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final RecentEpisode ep;
  final int? numero;
  final VoidCallback onTap;
  const _EpisodeCard({required this.ep, required this.numero, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _WideCard(
      imagen: ep.imagen,
      etiqueta: numero == null ? null : episodeLabel(numero!),
      titulo: ep.titulo,
      fecha: ep.fecha,
      onTap: onTap,
    );
  }
}

// ───────────────────── 3. Series recientes ─────────────────────

/// Sliver: debe ir directamente en el `CustomScrollView`.
class _RecentSeriesSection extends StatelessWidget {
  final Future<List<RecentSerie>> future;
  final void Function(RecentSerie) onOpen;
  final VoidCallback onRetry;
  const _RecentSeriesSection(
      {required this.future, required this.onOpen, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RecentSerie>>(
      future: future,
      builder: (context, snap) {
        final done = snap.connectionState == ConnectionState.done;
        // El error ya se muestra en el banner, con su botón de reintento.
        if (done && snap.hasError) return const SliverToBoxAdapter();
        final series = snap.data ?? const <RecentSerie>[];
        if (done && series.isEmpty) return const SliverToBoxAdapter();

        return SliverMainAxisGroup(
          slivers: [
            const SliverToBoxAdapter(child: _SectionTitle('Series recientes')),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2 / 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: done ? series.length : 6,
                itemBuilder: (_, i) => done
                    ? AnimeCard(
                        nombre: series[i].titulo,
                        imagen: series[i].imagen,
                        onTap: () => onOpen(series[i]),
                      )
                    : const DecoratedBox(
                        decoration:
                            BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardAll)),
              ),
            ),
          ],
        );
      },
    );
  }
}
