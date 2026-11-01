import 'package:flutter/material.dart';
import 'package:latanime_plugin/latanime_plugin.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';
import 'player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _plugin = LatanimePlugin();

  late Future<List<RecentSerie>> _seriesFuture;
  late Future<List<RecentEpisode>> _episodesFuture;

  @override
  void initState() {
    super.initState();
    _seriesFuture = _plugin.getRecentSeries();
    _episodesFuture = _plugin.getLatestEpisodes();
  }

  void _reloadSeries() => setState(() => _seriesFuture = _plugin.getRecentSeries());
  void _reloadEpisodes() => setState(() => _episodesFuture = _plugin.getLatestEpisodes());

  Future<void> _refresh() async {
    setState(() {
      _seriesFuture = _plugin.getRecentSeries();
      _episodesFuture = _plugin.getLatestEpisodes();
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
            builder: (_) => DetailScreen(nombre: s.titulo, url: s.url, imagen: s.imagen)),
      );

  /// URL tipo https://latanime.org/ver/ranma-2024-latino-episodio-29
  void _openEpisode(RecentEpisode ep) {
    final m = RegExp(r'^(.*)-episodio-(\d+)$').firstMatch(_lastSegment(ep.url));
    if (m == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo abrir el episodio')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
            slug: m.group(1)!, numero: int.parse(m.group(2)!), animeTitulo: ep.titulo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            _HeroSection(future: _seriesFuture, onOpen: _openSerie, onRetry: _reloadSeries),
            _RecentEpisodesSection(
                future: _episodesFuture, onOpen: _openEpisode, onRetry: _reloadEpisodes),
            _RecentSeriesSection(
                future: _seriesFuture, onOpen: _openSerie, onRetry: _reloadSeries),
          ],
        ),
      ),
    );
  }
}

String _lastSegment(String url) {
  final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? [];
  return segs.isEmpty ? url : segs.last;
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
            child: ErrorState(
                title: 'No se pudo cargar el catálogo',
                detail: snap.error.toString(),
                onRetry: onRetry),
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
                      Color(0x990B0B0D),
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

// ─────────────────── 2. Añadidos recientemente ───────────────────

class _RecentEpisodesSection extends StatelessWidget {
  final Future<List<RecentEpisode>> future;
  final void Function(RecentEpisode) onOpen;
  final VoidCallback onRetry;
  const _RecentEpisodesSection(
      {required this.future, required this.onOpen, required this.onRetry});

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
              ErrorState(
                  title: 'No se pudieron cargar los episodios',
                  detail: snap.error.toString(),
                  onRetry: onRetry),
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
          height: 170,
          builder: (i) => _EpisodeCard(ep: eps[i], onTap: () => onOpen(eps[i])),
        );
      },
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  final RecentEpisode ep;
  final VoidCallback onTap;
  const _EpisodeCard({required this.ep, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final num = RegExp(r'-episodio-(\d+)$').firstMatch(_lastSegment(ep.url))?.group(1);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(url: ep.imagen),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.center,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xB3000000)],
                      ),
                    ),
                  ),
                  const Center(
                      child: Icon(Icons.play_circle_outline_rounded,
                          size: 36, color: Colors.white70)),
                  if (ep.fecha.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.black87, borderRadius: BorderRadius.circular(2)),
                        child: Text(ep.fecha,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (num != null)
            Text('E$num',
                style: const TextStyle(
                    color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w800)),
          Text(ep.titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25)),
        ],
      ),
    );
  }
}

// ───────────────────── 3. Series recientes ─────────────────────

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
        if (done && snap.hasError) return const SizedBox.shrink();
        final series = snap.data ?? const <RecentSerie>[];
        if (done && series.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Series recientes'),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.5,
                crossAxisSpacing: 10,
                mainAxisSpacing: 16,
              ),
              itemCount: done ? series.length : 6,
              itemBuilder: (_, i) => done
                  ? AnimeCard(
                      nombre: series[i].titulo,
                      imagen: series[i].imagen,
                      onTap: () => onOpen(series[i]),
                    )
                  : const DecoratedBox(decoration: BoxDecoration(color: AppColors.surface)),
            ),
          ],
        );
      },
    );
  }
}
