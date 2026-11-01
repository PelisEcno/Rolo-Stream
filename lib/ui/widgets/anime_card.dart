import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Póster 2:3 con el título debajo, como en Crunchyroll.
class AnimeCard extends StatelessWidget {
  final String nombre;
  final String imagen;
  final VoidCallback onTap;

  const AnimeCard({super.key, required this.nombre, required this.imagen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(width: double.infinity, child: PosterImage(url: imagen)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            nombre,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class PosterImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  const PosterImage({super.key, required this.url, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: AppColors.surfaceHigh,
      child: const Icon(Icons.movie_outlined, color: AppColors.textMuted, size: 28),
    );
    if (url.isEmpty) return placeholder;
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => placeholder,
    );
  }
}

/// Título de sección con "VER TODO" opcional y carrusel horizontal debajo.
class SectionRow extends StatelessWidget {
  final String title;
  final int count;
  final Widget Function(int) builder;
  final VoidCallback? onSeeAll;
  final bool loading;
  final double itemWidth;
  final double height;

  const SectionRow({
    super.key,
    required this.title,
    required this.count,
    required this.builder,
    this.onSeeAll,
    this.loading = false,
    this.itemWidth = 128,
    this.height = 244,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (onSeeAll != null)
                TextButton(
                  onPressed: onSeeAll,
                  child: const Text('VER TODO',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: loading ? 6 : count,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => SizedBox(
              width: itemWidth,
              child: loading
                  ? const DecoratedBox(decoration: BoxDecoration(color: AppColors.surface))
                  : builder(i),
            ),
          ),
        ),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String title;
  final String? detail;
  final VoidCallback onRetry;
  const ErrorState({super.key, required this.title, this.detail, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(detail!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('REINTENTAR')),
          ],
        ),
      ),
    );
  }
}

class AnimeGrid extends StatelessWidget {
  final int count;
  final Widget Function(int) builder;
  const AnimeGrid({super.key, required this.count, required this.builder});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.52,
        crossAxisSpacing: 12,
        mainAxisSpacing: 16,
      ),
      itemCount: count,
      itemBuilder: (_, i) => builder(i),
    );
  }
}

class GridSkeleton extends StatelessWidget {
  const GridSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimeGrid(
      count: 9,
      builder: (_) => const DecoratedBox(decoration: BoxDecoration(color: AppColors.surface)),
    );
  }
}

/// Póster con badge de tipo (arriba) y año (abajo) y el título debajo.
class CatalogCard extends StatelessWidget {
  final String nombre;
  final String imagen;
  final String tipo;
  final String anio;
  final VoidCallback onTap;
  const CatalogCard({
    super.key,
    required this.nombre,
    required this.imagen,
    this.tipo = '',
    this.anio = '',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PosterImage(url: imagen),
                    if (tipo.isNotEmpty)
                      Positioned(
                        left: 0,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.only(
                                topRight: Radius.circular(2), bottomRight: Radius.circular(2)),
                          ),
                          child: Text(tipo.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    if (anio.isNotEmpty)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                              color: Colors.black87, borderRadius: BorderRadius.circular(2)),
                          child: Text(anio,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25)),
        ],
      ),
    );
  }
}
