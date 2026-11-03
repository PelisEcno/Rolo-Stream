import 'package:flutter/material.dart';
import '../../iptv/epg.dart';
import '../../iptv/iptv_models.dart';
import '../theme/app_theme.dart';
import 'anime_card.dart';

/// Guía de programación como línea de tiempo: el eje horario y los canales comparten el scroll
/// horizontal, y la columna con el nombre del canal se queda fija a la izquierda.
class EpgTimeline extends StatefulWidget {
  final List<Channel> channels;
  final void Function(Channel) onPlay;
  const EpgTimeline({super.key, required this.channels, required this.onPlay});

  static const pxPerMinute = 4.0;
  static const labelWidth = 104.0;
  static const rowHeight = 68.0;
  static const rulerHeight = 30.0;
  static const hoursAhead = 6;

  /// Inicio del eje: la media hora anterior a [now], para ver un poco de lo ya emitido.
  static DateTime windowStart(DateTime now) {
    final local = now.toLocal();
    final slot = DateTime(local.year, local.month, local.day, local.hour, local.minute >= 30 ? 30 : 0);
    return slot.subtract(const Duration(minutes: 30));
  }

  static double xOf(DateTime t, DateTime start) =>
      t.difference(start).inSeconds / 60 * pxPerMinute;

  /// Posición de [p] en el eje, recortada a la ventana visible. `null` si queda fuera.
  static ({double left, double width})? blockFor(EPGProgram p, DateTime start, DateTime end) {
    if (!p.fin.isAfter(start) || !p.inicio.isBefore(end)) return null;
    final from = p.inicio.isBefore(start) ? start : p.inicio;
    final to = p.fin.isAfter(end) ? end : p.fin;
    return (left: xOf(from, start), width: xOf(to, start) - xOf(from, start));
  }

  @override
  State<EpgTimeline> createState() => _EpgTimelineState();
}

class _EpgTimelineState extends State<EpgTimeline> {
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    // Se abre con "ahora" a la vista, justo después de la columna de canales.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_horizontal.hasClients) return;
      final now = DateTime.now();
      final x = EpgTimeline.xOf(now, EpgTimeline.windowStart(now));
      _horizontal.jumpTo((x - 24).clamp(0.0, _horizontal.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  /// Mantiene [child] fijo a la izquierda mientras el eje se desplaza.
  Widget _sticky(Widget child) => AnimatedBuilder(
        animation: _horizontal,
        builder: (_, c) => Transform.translate(
            offset: Offset(_horizontal.hasClients ? _horizontal.offset : 0, 0), child: c),
        child: child,
      );

  Widget _ruler(DateTime start, DateTime end) {
    final marks = <DateTime>[
      for (var t = start; t.isBefore(end); t = t.add(const Duration(minutes: 30))) t,
    ];
    return SizedBox(
      height: EpgTimeline.rulerHeight,
      child: Stack(
        children: [
          for (final t in marks)
            Positioned(
              left: EpgTimeline.labelWidth + EpgTimeline.xOf(t, start) + 6,
              top: 8,
              child: Text(EPGProgram.hora(t),
                  style: const TextStyle(
                      color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          _sticky(Container(width: EpgTimeline.labelWidth, color: AppColors.background)),
        ],
      ),
    );
  }

  Widget _row(Channel c, DateTime start, DateTime end, DateTime now) {
    final programas = EPGService.instance.scheduleFor(c)?.programas ?? const <EPGProgram>[];
    return InkWell(
      onTap: () => widget.onPlay(c),
      child: Container(
        height: EpgTimeline.rowHeight,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Stack(
          children: [
            for (final p in programas)
              if (EpgTimeline.blockFor(p, start, end) case final b?)
                Positioned(
                  left: EpgTimeline.labelWidth + b.left,
                  width: b.width,
                  top: 4,
                  bottom: 4,
                  child: _ProgramBlock(program: p, now: now),
                ),
            _sticky(_ChannelLabel(channel: c)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = EpgTimeline.windowStart(now);
    final end = start.add(const Duration(hours: EpgTimeline.hoursAhead));
    final width = EpgTimeline.labelWidth + EpgTimeline.xOf(end, start);
    final nowX = EpgTimeline.labelWidth + EpgTimeline.xOf(now, start);

    return SingleChildScrollView(
      controller: _horizontal,
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: width,
        child: Stack(
          children: [
            Column(
              children: [
                _ruler(start, end),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.channels.length,
                    itemExtent: EpgTimeline.rowHeight,
                    itemBuilder: (_, i) => _row(widget.channels[i], start, end, now),
                  ),
                ),
              ],
            ),
            // La línea de "ahora" atraviesa todos los canales.
            Positioned(
              left: nowX - 1,
              top: 0,
              bottom: 0,
              width: 2,
              child: const IgnorePointer(child: ColoredBox(color: AppColors.primary)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelLabel extends StatelessWidget {
  final Channel channel;
  const _ChannelLabel({required this.channel});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: EpgTimeline.labelWidth,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: AppColors.background,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: Container(
              width: 30,
              height: 30,
              color: AppColors.surfaceHigh,
              child: channel.logo == null
                  ? const Icon(Icons.tv_rounded, size: 16, color: AppColors.textMuted)
                  : PosterImage(url: channel.logo!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(channel.nombre,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, height: 1.15)),
          ),
        ],
      ),
    );
  }
}

class _ProgramBlock extends StatelessWidget {
  final EPGProgram program;
  final DateTime now;
  const _ProgramBlock({required this.program, required this.now});

  @override
  Widget build(BuildContext context) {
    final live = program.isLiveAt(now);
    final past = program.fin.isBefore(now);
    return Container(
      margin: const EdgeInsets.only(right: 2),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: past ? AppColors.surface : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Lo ya emitido del programa en curso, como fondo.
          if (live)
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: program.progressAt(now),
              child: const ColoredBox(color: Color(0x33F47521)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(program.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: past ? AppColors.textMuted : Colors.white)),
                const SizedBox(height: 2),
                Text(program.rango,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
