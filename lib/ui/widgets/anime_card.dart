import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../services/app_error.dart';
import '../../services/mediaflow_service.dart';
import '../theme/app_theme.dart';

/// Se encoge al tocar y crece un poco con el cursor encima.
class PressScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double hoverScale;
  const PressScale({super.key, required this.child, this.onTap, this.hoverScale = 1.03});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _hover = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.96 : (_hover ? widget.hoverScale : 1),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Imagen algo mayor que su marco, que se desplaza más despacio que el scroll.
///
/// Usa `Flow` para repintar sin reconstruir nada al hacer scroll.
class ParallaxImage extends StatelessWidget {
  final String url;
  const ParallaxImage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return PosterImage(url: url);
    return Flow(
      delegate: _ParallaxDelegate(scrollable: scrollable, item: context),
      children: [PosterImage(url: url)],
    );
  }
}

class _ParallaxDelegate extends FlowDelegate {
  final ScrollableState scrollable;
  final BuildContext item;
  _ParallaxDelegate({required this.scrollable, required this.item})
      : super(repaint: scrollable.position);

  /// Parte de la imagen que sobra del marco: es el recorrido máximo del efecto.
  static const _overflow = 0.12;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) => BoxConstraints.tight(
      Size(constraints.biggest.width * (1 + _overflow), constraints.biggest.height * (1 + _overflow)));

  @override
  void paintChildren(FlowPaintingContext context) {
    final extra = context.getChildSize(0)! - context.size as Size;
    var dx = -extra.width / 2;
    var dy = -extra.height / 2;

    final viewport = scrollable.context.findRenderObject();
    final box = item.findRenderObject();
    if (viewport is RenderBox && box is RenderBox && viewport.hasSize && box.hasSize) {
      final center = box.localToGlobal(box.size.center(Offset.zero), ancestor: viewport);
      if (axisDirectionToAxis(scrollable.axisDirection) == Axis.horizontal) {
        final f = (center.dx / viewport.size.width - 0.5).clamp(-1.0, 1.0);
        dx -= f * extra.width / 2;
      } else {
        final f = (center.dy / viewport.size.height - 0.5).clamp(-1.0, 1.0);
        dy -= f * extra.height / 2;
      }
    }
    context.paintChild(0, transform: Matrix4.translationValues(dx, dy, 0));
  }

  @override
  bool shouldRepaint(_ParallaxDelegate old) => old.scrollable != scrollable || old.item != item;
}

/// Degradado inferior para que el texto sobre un póster se lea siempre.
class PosterScrim extends StatelessWidget {
  const PosterScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.45, 0.75, 1],
          colors: [Colors.transparent, Color(0xA6000000), Color(0xF0000000)],
        ),
      ),
    );
  }
}

/// Póster 2:3 con el título sobre el degradado.
class AnimeCard extends StatelessWidget {
  final String nombre;
  final String imagen;
  final VoidCallback onTap;

  const AnimeCard({super.key, required this.nombre, required this.imagen, required this.onTap});

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
            Positioned(left: 8, right: 8, bottom: 8, child: _PosterTitle(nombre)),
          ],
        ),
      ),
    );
  }
}

class _PosterTitle extends StatelessWidget {
  final String text;
  const _PosterTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.2),
    );
  }
}

/// Marco de los pósters.
class RoundedPoster extends StatelessWidget {
  final Widget child;
  const RoundedPoster({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: AppRadius.cardAll, child: child);
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
    this.height = 192,
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
            // Sin rebote y sin ser el scroll "primario": el vertical es el de la pantalla.
            physics: const ClampingScrollPhysics(),
            primary: false,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: loading ? 6 : count,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => SizedBox(
              width: itemWidth,
              child: loading
                  ? const DecoratedBox(
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardAll))
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
            Icon(icon, size: 48, color: AppColors.textMuted),
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

/// Error de una carga, explicado según su causa ([AppError]).
///
/// Si el proxy no responde lo reinicia aquí mismo y vuelve a intentar la carga.
class ErrorState extends StatefulWidget {
  final Object? error;
  final VoidCallback onRetry;

  /// Sustituye al mensaje según la causa, para errores que ya vienen explicados.
  final String? message;
  final Future<bool> Function() restartEngine;

  const ErrorState({
    super.key,
    required this.error,
    required this.onRetry,
    this.message,
    this.restartEngine = MediaFlowService.ensureRunning,
  });

  @override
  State<ErrorState> createState() => _ErrorStateState();
}

class _ErrorStateState extends State<ErrorState> {
  late final AppError _error = AppError.from(widget.error);
  late bool _restarting = _error.kind == AppErrorKind.engine;
  bool _restartFailed = false;

  @override
  void initState() {
    super.initState();
    if (_restarting) _restart();
  }

  Future<void> _restart() async {
    final ok = await widget.restartEngine();
    if (!mounted) return;
    if (ok) {
      widget.onRetry();
    } else {
      setState(() {
        _restarting = false;
        _restartFailed = true;
      });
    }
  }

  IconData get _icon => switch (_error.kind) {
        AppErrorKind.network => Icons.wifi_off_rounded,
        AppErrorKind.serverDown => Icons.dns_outlined,
        AppErrorKind.engine => Icons.settings_backup_restore_rounded,
        AppErrorKind.unknown => Icons.error_outline_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final text = _restartFailed
        ? 'No se pudo reiniciar el motor de reproducción. Cierra y vuelve a abrir la app.'
        : widget.message ?? _error.message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_restarting)
                const SizedBox(
                    width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3))
              else
                Icon(_icon, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
              if (!_restarting) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: widget.onRetry,
                  child: Text(_error.kind == AppErrorKind.network ? 'RECARGAR' : 'REINTENTAR'),
                ),
              ],
            ],
          ),
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
        childAspectRatio: 2 / 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
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
      builder: (_) => const DecoratedBox(
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: AppRadius.cardAll)),
    );
  }
}

/// Póster con badge de tipo y año, y el título sobre el degradado.
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
    return PressScale(
      onTap: onTap,
      child: RoundedPoster(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ParallaxImage(url: imagen),
            const PosterScrim(),
            if (tipo.isNotEmpty)
              Positioned(
                left: 0,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  color: AppColors.primary,
                  child: Text(tipo.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900)),
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (anio.isNotEmpty)
                    Text(anio,
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w700)),
                  _PosterTitle(nombre),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
