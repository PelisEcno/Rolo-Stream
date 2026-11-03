import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../theme/app_theme.dart';

/// Buffer del reproductor: 128 MB de demuxer.
const kPlayerBufferBytes = 128 * 1024 * 1024;

/// Opciones de FFmpeg para reconectar solo ante cortes de red y errores 5xx del servidor.
const _lavfReconnect = 'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
    'reconnect_on_http_error=5xx,reconnect_delay_max=4';

/// Brillo de la app al abrir el reproductor: el gesto de brillo parte de este valor.
double? _appBrightness;

/// Lee el brillo actual para que el gesto de brillo parta de él.
Future<void> loadAppBrightness() async {
  try {
    _appBrightness = await ScreenBrightness.instance.application;
  } catch (_) {
    // Sin brillo disponible el gesto parte del valor por defecto.
  }
}

double? currentAppBrightness() => _appBrightness;

void setAppBrightness(double value) {
  _appBrightness = value;
  ScreenBrightness.instance.setApplicationScreenBrightness(value).catchError((Object _) {});
}

void resetAppBrightness() {
  ScreenBrightness.instance.resetApplicationScreenBrightness().catchError((Object _) {});
}

/// Crea un `Player` con buffer grande y pre-buffering agresivo.
///
/// Las propiedades de mpv se aplican en cuanto el reproductor está listo; si alguna no existe
/// en la build de libmpv de la plataforma se ignora (no afecta a la reproducción).
Player createPremiumPlayer({MPVLogLevel logLevel = MPVLogLevel.error}) {
  loadAppBrightness();
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
      // Si se vacía el buffer, mpv espera a tener 3 s antes de reanudar en vez de tartamudear.
      'cache-pause': 'yes',
      'cache-pause-wait': '3',
      // Por defecto mpv espera 60 s a un servidor que no responde.
      'network-timeout': '10',
      'demuxer-lavf-o': _lavfReconnect,
      'stream-lavf-o': _lavfReconnect,
    };
    for (final e in props.entries) {
      platform.setProperty(e.key, e.value).catchError((_) {});
    }
  }
  return player;
}

/// `hwdec` del reproductor: en iOS, VideoToolbox falla con muchos streams IPTV
/// (`Error while decoding frame`) y se decodifica por software. `null` deja el de `media_kit`.
String? hwdecFor(TargetPlatform platform) => platform == TargetPlatform.iOS ? 'no' : null;

VideoController createPremiumController(Player player) => VideoController(
      player,
      configuration: VideoControllerConfiguration(hwdec: hwdecFor(defaultTargetPlatform)),
    );

enum PlaybackPhase { idle, connecting, retrying, playing, failed }

/// Reabre la fuente si la posición del video deja de avanzar, al arrancar o en mitad de la
/// reproducción. Mientras tanto la reproducción no se corta: solo cambia el mensaje de [phase].
///
/// Se mira la posición porque `Player.state.playing` solo indica que no está en pausa (es `true`
/// aunque el video no haya empezado) y `buffering` pasa a `false` en cada `Player.open`.
///
/// Cada intento espera más que el anterior ([attemptTimeouts]): un stream que tarda 15 s en
/// arrancar reiniciado siempre a los 10 s no llegaría a verse nunca. Agotados, llama a [onGiveUp].
class PlaybackWatchdog {
  PlaybackWatchdog(
    Player player, {
    required Future<void> Function(Duration resumeAt) reopen,
    VoidCallback? onGiveUp,
  }) : this.withSource(
          position: player.stream.position,
          shouldWatch: () => player.state.playing && !player.state.completed,
          reopen: reopen,
          onGiveUp: onGiveUp,
        );

  /// Con cualquier motor, y sin libmpv en las pruebas.
  PlaybackWatchdog.withSource({
    required Stream<Duration> position,
    required bool Function() shouldWatch,
    required this.reopen,
    this.onGiveUp,
    this.attemptTimeouts = const [
      Duration(seconds: 10),
      Duration(seconds: 15),
      Duration(seconds: 20)
    ],
    this.stallTimeout = const Duration(seconds: 12),
  }) : _shouldWatch = shouldWatch {
    _sub = position.listen(_onPosition);
  }

  final bool Function() _shouldWatch;
  final Future<void> Function(Duration resumeAt) reopen;
  final VoidCallback? onGiveUp;
  final List<Duration> attemptTimeouts;
  final Duration stallTimeout;

  final phase = ValueNotifier<PlaybackPhase>(PlaybackPhase.idle);

  /// Avance necesario para dar el video por arrancado, y salto máximo que cuenta como avance:
  /// `Player.open` y los `seek` también mueven la posición, sin que se esté reproduciendo nada.
  static const _startedAfter = Duration(seconds: 1);
  static const _maxStep = Duration(seconds: 2);

  late final StreamSubscription<Duration> _sub;
  Timer? _timer;
  int _attempt = 0;
  Duration? _last;
  Duration _progress = Duration.zero;
  Duration _lastGood = Duration.zero;

  /// La línea de tiempo del reproductor cambió (se abrió otro tramo): lo anterior ya no sirve de
  /// referencia, pero los intentos gastados siguen contando.
  void resetPosition() {
    _last = null;
    _progress = Duration.zero;
    _lastGood = Duration.zero;
  }

  /// Aún no hay nada que vigilar (por ejemplo, se está resolviendo el servidor).
  void connecting() {
    _timer?.cancel();
    phase.value = PlaybackPhase.connecting;
  }

  /// Llamar justo antes de abrir una fuente nueva.
  void begin() {
    _attempt = 0;
    _last = null;
    _progress = Duration.zero;
    _lastGood = Duration.zero;
    phase.value = PlaybackPhase.connecting;
    _arm(attemptTimeouts.first);
  }

  void stop() {
    _timer?.cancel();
    phase.value = PlaybackPhase.idle;
  }

  void _arm(Duration timeout) {
    _timer?.cancel();
    _timer = Timer(timeout, _onTimeout);
  }

  void _onPosition(Duration pos) {
    final last = _last;
    _last = pos;
    if (last == null) return;
    final step = pos - last;
    if (step <= Duration.zero || step > _maxStep) return;
    final current = phase.value;
    if (current == PlaybackPhase.idle || current == PlaybackPhase.failed) return;

    _lastGood = pos;
    if (current == PlaybackPhase.playing) {
      _arm(stallTimeout);
      return;
    }
    _progress += step;
    if (_progress >= _startedAfter) {
      _attempt = 0;
      phase.value = PlaybackPhase.playing;
      _arm(stallTimeout);
    }
  }

  void _onTimeout() {
    // Ya arrancó: una pausa del usuario o el final del video no son un atasco.
    if (phase.value == PlaybackPhase.playing && !_shouldWatch()) {
      _arm(stallTimeout);
      return;
    }
    // Un atasco en plena reproducción empieza de nuevo por el primer reintento.
    _attempt++;
    if (_attempt >= attemptTimeouts.length) {
      phase.value = PlaybackPhase.failed;
      onGiveUp?.call();
      return;
    }
    _progress = Duration.zero;
    phase.value = PlaybackPhase.retrying;
    _arm(attemptTimeouts[_attempt]);
    reopen(_lastGood).catchError((Object _) {
      // El temporizador ya armado cuenta este intento como fallido.
    });
  }

  void dispose() {
    _timer?.cancel();
    _sub.cancel();
    phase.dispose();
  }
}

/// Reabre [media] y vuelve a [resumeAt] (en un directo no hay posición a la que volver).
Future<void> reopenAt(Player player, Media media, Duration resumeAt) async {
  await player.open(media);
  if (resumeAt < const Duration(seconds: 2)) return;
  final known = await player.stream.duration
      .firstWhere((d) => d > Duration.zero)
      .timeout(const Duration(seconds: 10), onTimeout: () => Duration.zero);
  if (known > Duration.zero) await player.seek(resumeAt);
}

/// Marca discreta en la esquina inferior derecha. Queda por debajo del botón de pantalla completa
/// y no captura toques.
class PlayerWatermark extends StatelessWidget {
  const PlayerWatermark({super.key});

  @override
  Widget build(BuildContext context) {
    return const Positioned(
      right: 12,
      bottom: 4,
      child: IgnorePointer(
        child: Text(
          'ROLOSTREAM',
          style: TextStyle(
            color: Color(0x4DFFFFFF),
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}

/// Spinner con el estado de la conexión. Durante un buffering normal no lleva texto.
class PlaybackStatusOverlay extends StatelessWidget {
  final Stream<bool> buffering;

  /// Se lee al mostrar el spinner, no al crear el widget: esto se construye mientras el video aún
  /// carga y el aviso de que ya cargó puede llegar antes de empezar a escuchar [buffering].
  final bool Function() isBuffering;
  final ValueListenable<PlaybackPhase> phase;
  final String connectingLabel;
  const PlaybackStatusOverlay({
    super.key,
    required this.buffering,
    required this.isBuffering,
    required this.phase,
    required this.connectingLabel,
  });

  Widget _spinner([String? label]) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<PlaybackPhase>(
        valueListenable: phase,
        builder: (context, p, _) {
          if (p == PlaybackPhase.connecting) return _spinner(connectingLabel);
          if (p == PlaybackPhase.retrying) return _spinner('Reintentando...');
          if (p == PlaybackPhase.failed) return const SizedBox.shrink();
          return StreamBuilder<bool>(
            stream: buffering,
            initialData: isBuffering(),
            builder: (context, snap) => snap.data == true ? _spinner() : const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// Pista de audio que hay que fijar en un directo, o `null` si no hace falta.
///
/// Con `auto`, mpv puede quedarse sin audio en canales cuyas pistas no declaran idioma ni pista
/// por defecto. Se fija la primera real; si ya hay una elegida se respeta.
AudioTrack? liveAudioTrackToForce(Tracks tracks, Track current) {
  final id = current.audio.id;
  if (id != 'auto' && id != 'no') return null;
  for (final t in tracks.audio) {
    if (t.id != 'auto' && t.id != 'no') return t;
  }
  return null;
}

/// Botón central de un directo: solo aparece si está parado, para volver a reproducir.
/// Un canal en vivo no se puede pausar.
class LivePlayButton extends StatelessWidget {
  final Stream<bool> playing;

  /// Se lee al mostrar el botón, no al crear el widget: el aviso de que empezó a reproducir puede
  /// llegar antes de empezar a escuchar [playing].
  final bool Function() isPlaying;
  final VoidCallback onPlay;
  const LivePlayButton({
    super.key,
    required this.playing,
    required this.isPlaying,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: playing,
      initialData: isPlaying(),
      builder: (context, snap) {
        if (snap.data == true) return const SizedBox.shrink();
        return IconButton(
          tooltip: 'Reproducir',
          iconSize: 56,
          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
          onPressed: onPlay,
        );
      },
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Text('EN VIVO',
          style: TextStyle(
              color: Colors.black, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
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
                          fontWeight: FontWeight.w700, color: selected ? AppColors.primary : null)),
                  trailing:
                      selected ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
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
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
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

/// Barra de progreso para motores sin controles propios.
///
/// Lee posición y duración por su cuenta en vez de recibir valores fijos, porque en pantalla completa
/// el widget puede vivir mucho más que el video que había al crearlo.
class TimelineBar extends StatefulWidget {
  final Stream<Duration> position;
  final Duration Function() currentPosition;
  final Duration Function() duration;
  final void Function(Duration) onSeek;
  const TimelineBar({
    super.key,
    required this.position,
    required this.currentPosition,
    required this.duration,
    required this.onSeek,
  });

  static String format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = two(d.inMinutes % 60);
    final s = two(d.inSeconds % 60);
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  State<TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends State<TimelineBar> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: widget.position,
      builder: (context, _) => _bar(widget.currentPosition(), widget.duration()),
    );
  }

  Widget _bar(Duration position, Duration duration) {
    // Hasta conocer la duración, `Slider` necesita un máximo mayor que su mínimo.
    final max = duration > Duration.zero ? duration.inMilliseconds.toDouble() : 1.0;
    final value = (_dragging ?? position.inMilliseconds.toDouble()).clamp(0.0, max);
    return Row(
      children: [
        Text(
          '${TimelineBar.format(Duration(milliseconds: value.round()))} / '
          '${TimelineBar.format(duration)}',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.4),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: AppColors.primary,
              thumbColor: AppColors.primary,
              inactiveTrackColor: const Color(0x3DFFFFFF),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Slider(
                value: value,
                max: max,
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: (v) {
                  setState(() => _dragging = null);
                  widget.onSeek(Duration(milliseconds: v.round()));
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tema de los controles. Un directo no tiene barra de progreso, ni nada para buscar o pausar.
///
/// No hay que tocar los márgenes inferiores: `media_kit` excluye `16 + margen + buttonBarHeight`
/// de la zona que recibe los toques, y en la vista normal (unos 210 px de alto) cada píxel
/// añadido deja sin respuesta una parte mayor del video.
MaterialVideoControlsThemeData premiumControlsTheme(
  MaterialVideoControlsThemeData base, {
  required bool live,
  required Widget quality,
  required Widget livePlayButton,
  void Function(double)? onVolumeChanged,
  double? initialVolume,
  void Function(double)? onBrightnessChanged,
  double? initialBrightness,
  void Function()? onBrightnessReset,
}) {
  return base.copyWith(
    visibleOnMount: true,
    controlsHoverDuration: const Duration(seconds: 5),
    displaySeekBar: !live,
    seekGesture: !live,
    seekOnDoubleTap: !live,
    seekOnDoubleTapEnabledWhileControlsVisible: !live,
    speedUpOnLongPress: false,
    volumeGesture: true,
    brightnessGesture: true,
    gesturesEnabledWhileControlsVisible: true,
    onVolumeChanged: onVolumeChanged,
    initialVolume: initialVolume,
    onBrightnessChanged: onBrightnessChanged,
    initialBrightness: initialBrightness,
    onBrightnessReset: onBrightnessReset,
    // El spinner lo pinta `PlaybackStatusOverlay`, que además dice qué está pasando.
    bufferingIndicatorBuilder: (_) => const SizedBox.shrink(),
    seekBarPositionColor: AppColors.primary,
    seekBarThumbColor: AppColors.primary,
    primaryButtonBar: live ? [livePlayButton] : null,
    bottomButtonBar: [
      if (live) const _LiveBadge() else const MaterialPositionIndicator(),
      const Spacer(),
      quality,
      const MaterialFullscreenButton(),
    ],
  );
}

/// Vídeo con los controles estilo RoloStream: marca de agua, gestos (doble toque ±10 s,
/// deslizar para volumen y brillo), selector de calidad y estado de la conexión.
class PremiumVideo extends StatelessWidget {
  final Player player;
  final VideoController controller;
  final ValueListenable<PlaybackPhase> phase;

  /// `true` directo, `false` bajo demanda, `null` lo decide la duración (0 = directo).
  final bool? live;
  final String connectingLabel;

  const PremiumVideo({
    super.key,
    required this.player,
    required this.controller,
    required this.phase,
    required this.connectingLabel,
    this.live,
  });

  MaterialVideoControlsThemeData _theme(MaterialVideoControlsThemeData base, bool isLive) {
    return premiumControlsTheme(
      base,
      live: isLive,
      quality: QualityButton(player: player),
      livePlayButton: LivePlayButton(
        playing: player.stream.playing,
        isPlaying: () => player.state.playing,
        onPlay: player.play,
      ),
      onVolumeChanged: (v) => player.setVolume(v * 100),
      initialVolume: player.state.volume / 100,
      onBrightnessChanged: setAppBrightness,
      initialBrightness: _appBrightness,
      onBrightnessReset: resetAppBrightness,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.stream.duration,
      initialData: player.state.duration,
      builder: (context, snap) {
        final isLive = live ?? (snap.data ?? Duration.zero) == Duration.zero;
        return MaterialVideoControlsTheme(
          normal: _theme(kDefaultMaterialVideoControlsThemeData, isLive),
          fullscreen: _theme(kDefaultMaterialVideoControlsThemeDataFullscreen, isLive),
          child: Video(
            controller: controller,
            // Los controles también se construyen en pantalla completa: la marca de agua y el
            // estado viajan con ellos.
            controls: (state) => Stack(
              fit: StackFit.expand,
              children: [
                const PlayerWatermark(),
                MaterialVideoControls(state),
                PlaybackStatusOverlay(
                  buffering: player.stream.buffering,
                  isBuffering: () => player.state.buffering,
                  phase: phase,
                  connectingLabel: connectingLabel,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
