import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../theme/app_theme.dart';

/// Buffer del reproductor: 128 MB de demuxer.
const kPlayerBufferBytes = 128 * 1024 * 1024;

/// Opciones de FFmpeg para reconectar solo ante cortes de red y errores 5xx del servidor.
const _lavfReconnect = 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
    'reconnect_on_http_error=5xx,reconnect_delay_max=4';

/// Crea un `Player` con buffer grande y pre-buffering agresivo.
///
/// Las propiedades de mpv se aplican en cuanto el reproductor está listo; si alguna no existe
/// en la build de libmpv de la plataforma se ignora (no afecta a la reproducción).
Player createPremiumPlayer({MPVLogLevel logLevel = MPVLogLevel.error}) {
  final player = Player(
    configuration: PlayerConfiguration(bufferSize: kPlayerBufferBytes, logLevel: logLevel),
  );
  final platform = player.platform;
  if (platform is NativePlayer) {
    const props = {
      'cache': 'yes',
      'demuxer-max-bytes': '$kPlayerBufferBytes',
      'demuxer-max-back-bytes': '${32 * 1024 * 1024}',
      'demuxer-readahead-secs': '120',
      'cache-secs': '120',
      // Si se vacía el buffer, mpv espera a tener 6 s antes de reanudar en vez de tartamudear.
      'cache-pause': 'yes',
      'cache-pause-wait': '6',
      'demuxer-lavf-o': _lavfReconnect,
      'stream-lavf-o': _lavfReconnect,
    };
    for (final e in props.entries) {
      platform.setProperty(e.key, e.value).catchError((_) {});
    }
  }
  return player;
}

/// Si el buffer lleva demasiado tiempo vacío, vuelve a abrir la fuente donde se quedó.
///
/// La reproducción no se corta mientras tanto: el spinner de buffering lo pone la UI y esta
/// clase solo actúa si el atasco dura [stallTimeout]. Tras [maxAttempts] intentos seguidos
/// deja de insistir y llama a [onGiveUp].
class StallRecovery {
  StallRecovery(
    Player player, {
    required Future<void> Function(Duration resumeAt) reopen,
    VoidCallback? onGiveUp,
  }) : this.withSource(
          buffering: player.stream.buffering,
          isBuffering: () => player.state.buffering,
          hasMedia: () => player.state.playlist.medias.isNotEmpty,
          position: () => player.state.position,
          reopen: reopen,
          onGiveUp: onGiveUp,
        );

  /// Sin `Player` de por medio, para poder probar la lógica sin libmpv.
  @visibleForTesting
  StallRecovery.withSource({
    required Stream<bool> buffering,
    required bool Function() isBuffering,
    required bool Function() hasMedia,
    required Duration Function() position,
    required this.reopen,
    this.onGiveUp,
    this.stallTimeout = const Duration(seconds: 12),
    this.healthyAfter = const Duration(seconds: 5),
    this.maxAttempts = 3,
  })  : _isBuffering = isBuffering,
        _hasMedia = hasMedia,
        _position = position {
    _sub = buffering.listen(_onBuffering);
  }

  final bool Function() _isBuffering;
  final bool Function() _hasMedia;
  final Duration Function() _position;
  final Future<void> Function(Duration resumeAt) reopen;
  final VoidCallback? onGiveUp;
  final Duration stallTimeout;

  /// Tiempo sin buffering para dar la fuente por recuperada. No basta con ver `buffering=false`:
  /// `Player.open` lo emite en cada reapertura, aunque la fuente siga caída.
  final Duration healthyAfter;
  final int maxAttempts;

  /// `true` mientras se está intentando recuperar la fuente.
  final reconnecting = ValueNotifier<bool>(false);

  late final StreamSubscription<bool> _sub;
  Timer? _stall;
  Timer? _healthy;
  int _attempts = 0;
  bool _disposed = false;

  void _onBuffering(bool buffering) {
    _stall?.cancel();
    _healthy?.cancel();
    if (buffering) {
      _stall = Timer(stallTimeout, _recover);
    } else {
      _healthy = Timer(healthyAfter, () {
        _attempts = 0;
        reconnecting.value = false;
      });
    }
  }

  Future<void> _recover() async {
    if (!_hasMedia()) return;
    if (_attempts >= maxAttempts) {
      reconnecting.value = false;
      onGiveUp?.call();
      return;
    }
    _attempts++;
    reconnecting.value = true;
    try {
      await reopen(_position());
    } catch (_) {
      // Si falla la reapertura, el siguiente ciclo de buffering lo vuelve a intentar.
    }
    if (_disposed) return;
    // Si la fuente sigue sin llenar el buffer, se reintenta pasado otro [stallTimeout].
    if (_isBuffering()) {
      _stall?.cancel();
      _stall = Timer(stallTimeout, _recover);
    }
  }

  /// Reabre [media] y vuelve a [resumeAt] (en un directo no hay posición a la que volver).
  static Future<void> reopenAt(Player player, Media media, Duration resumeAt) async {
    await player.open(media);
    if (resumeAt < const Duration(seconds: 2)) return;
    final known = await player.stream.duration
        .firstWhere((d) => d > Duration.zero)
        .timeout(const Duration(seconds: 10), onTimeout: () => Duration.zero);
    if (known > Duration.zero) await player.seek(resumeAt);
  }

  void dispose() {
    _disposed = true;
    _stall?.cancel();
    _healthy?.cancel();
    _sub.cancel();
    reconnecting.dispose();
  }
}

/// Logo de RoloStream en la esquina inferior derecha, al 40 % y sin capturar toques.
/// Ocupa los 38 px inferiores, por debajo de la barra de controles (ver [_controlsBottomInset]).
class PlayerWatermark extends StatelessWidget {
  const PlayerWatermark({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 8,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset('assets/images/rolostream_logo.png',
                width: 30, height: 30, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
    );
  }
}

/// Spinner de buffering (la reproducción no se detiene por él) y aviso de reconexión.
class _BufferingOverlay extends StatelessWidget {
  final Player player;
  final ValueListenable<bool>? reconnecting;
  const _BufferingOverlay({required this.player, this.reconnecting});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: StreamBuilder<bool>(
        stream: player.stream.buffering,
        initialData: player.state.buffering,
        builder: (context, snap) {
          if (snap.data != true) return const SizedBox.shrink();
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (reconnecting != null)
                  ValueListenableBuilder<bool>(
                    valueListenable: reconnecting!,
                    builder: (_, r, __) => r
                        ? const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: Text('Reconectando…',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Botón para elegir la calidad cuando la fuente es una master playlist HLS con varias variantes.
/// No se dibuja si el stream solo tiene una.
class QualityButton extends StatelessWidget {
  final Player player;
  const QualityButton({super.key, required this.player});

  /// Variantes reales (sin las pistas virtuales `auto` y `no`), de mayor a menor resolución.
  static List<VideoTrack> variantsOf(Tracks tracks) {
    final list = [
      for (final t in tracks.video)
        if (t.id != 'auto' && t.id != 'no' && ((t.h ?? 0) > 0 || (t.bitrate ?? 0) > 0)) t,
    ];
    list.sort((a, b) => _rank(b).compareTo(_rank(a)));
    return list;
  }

  static int _rank(VideoTrack t) => (t.h ?? 0) * 1000000 + (t.bitrate ?? 0) ~/ 1000;

  static String labelOf(VideoTrack t) {
    if ((t.h ?? 0) > 0) return '${t.h}p';
    return '${((t.bitrate ?? 0) / 1000000).toStringAsFixed(1)} Mbps';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Tracks>(
      stream: player.stream.tracks,
      initialData: player.state.tracks,
      builder: (context, snap) {
        final variants = variantsOf(snap.data ?? const Tracks());
        if (variants.length < 2) return const SizedBox.shrink();
        return IconButton(
          tooltip: 'Calidad',
          icon: const Icon(Icons.high_quality_rounded, color: Colors.white),
          onPressed: () => _showSheet(context, variants),
        );
      },
    );
  }

  void _showSheet(BuildContext context, List<VideoTrack> variants) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceHigh,
      builder: (ctx) => SafeArea(
        child: StreamBuilder<Track>(
          stream: player.stream.track,
          initialData: player.state.track,
          builder: (context, snap) {
            final current = snap.data?.video;
            final auto = current == null || current.id == 'auto';
            Widget row(String label, bool selected, VideoTrack track) => ListTile(
                  dense: true,
                  title: Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.primary : null)),
                  trailing: selected
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  onTap: () {
                    player.setVideoTrack(track);
                    Navigator.pop(ctx);
                  },
                );
            return ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('CALIDAD',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                ),
                row('Automática', auto, VideoTrack.auto()),
                for (final v in variants) row(labelOf(v), !auto && current.id == v.id, v),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Hueco bajo la barra de controles para que el botón de pantalla completa no pise la marca de agua.
const _controlsBottomInset = 40.0;

/// Vídeo con los controles estilo RoloStream: marca de agua, gestos (doble toque ±10 s,
/// deslizar para volumen y brillo), selector de calidad y spinner de buffering.
///
/// La barra de progreso y los gestos para buscar (arrastrar, doble toque) se desactivan en los directos
/// (los que no informan de duración).
class PremiumVideo extends StatelessWidget {
  final Player player;
  final VideoController controller;
  final ValueListenable<bool>? reconnecting;
  const PremiumVideo({
    super.key,
    required this.player,
    required this.controller,
    this.reconnecting,
  });

  MaterialVideoControlsThemeData _theme(MaterialVideoControlsThemeData base, bool live) {
    return base.copyWith(
      displaySeekBar: !live,
      seekGesture: !live,
      seekOnDoubleTap: !live,
      volumeGesture: true,
      brightnessGesture: true,
      gesturesEnabledWhileControlsVisible: true,
      seekOnDoubleTapEnabledWhileControlsVisible: true,
      // El spinner lo pinta `_BufferingOverlay`, que además avisa de las reconexiones.
      bufferingIndicatorBuilder: (_) => const SizedBox.shrink(),
      seekBarPositionColor: AppColors.primary,
      seekBarThumbColor: AppColors.primary,
      bottomButtonBarMargin:
          const EdgeInsets.only(left: 16, right: 8, bottom: _controlsBottomInset),
      seekBarMargin: const EdgeInsets.only(left: 16, right: 16, bottom: _controlsBottomInset),
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const Spacer(),
        QualityButton(player: player),
        const MaterialFullscreenButton(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, snap) {
        final live = (snap.data ?? Duration.zero) == Duration.zero;
        return MaterialVideoControlsTheme(
          normal: _theme(kDefaultMaterialVideoControlsThemeData, live),
          fullscreen: _theme(kDefaultMaterialVideoControlsThemeDataFullscreen, live),
          child: Video(
            controller: controller,
            // Los controles también se construyen en pantalla completa: la marca de agua y el
            // spinner viajan con ellos.
            controls: (state) => Stack(
              fit: StackFit.expand,
              children: [
                const PlayerWatermark(),
                MaterialVideoControls(state),
                _BufferingOverlay(player: player, reconnecting: reconnecting),
              ],
            ),
          ),
        );
      },
    );
  }
}
