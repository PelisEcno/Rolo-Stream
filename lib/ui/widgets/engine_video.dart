import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'premium_player.dart';

/// Una opción elegible del stream: calidad o pista de audio.
class QualityOption {
  final int id;
  final String label;
  const QualityOption(this.id, this.label);
}

const kPlaybackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

String speedLabel(double speed) =>
    '${speed == speed.roundToDouble() ? speed.toInt() : speed}x';

/// Lo que los controles necesitan de un motor de video. Así no dependen de uno concreto y se pueden
/// probar sin librerías nativas.
abstract class PlaybackModel {
  Stream<Duration> get positionStream;
  Duration get position;
  Duration get duration;
  ValueListenable<bool> get playing;
  Stream<bool> get bufferingStream;
  bool get buffering;
  double get volume;
  set volume(double value);
  ValueListenable<double> get speed;
  void setSpeed(double value);
  ValueListenable<List<QualityOption>> get qualities;
  int? get activeQuality;
  void selectQuality(int id);
  ValueListenable<List<QualityOption>> get audioTracks;
  int? get activeAudioTrack;
  void selectAudioTrack(int id);
  void play();
  void pause();
  Future<void> seek(Duration position);
}

/// Motor que el reproductor puede abrir, cambiar de fuente y cerrar.
abstract class VideoEngine implements PlaybackModel {
  String get name;
  Stream<String> get errors;
  bool get completed;
  Future<void> open(String url, {Duration start, Map<String, String>? headers});
  void stop();
  Widget surface();
  void dispose();
}

/// Video con controles al estilo Netflix para los motores que no son `media_kit`: ±10 s, velocidad,
/// audio, calidad, siguiente episodio, gestos de volumen y brillo, y marca de agua.
class EngineVideoView extends StatefulWidget {
  final PlaybackModel model;
  final Widget surface;
  final ValueListenable<PlaybackPhase> phase;
  final String connectingLabel;
  final bool fullscreen;

  /// Se muestra arriba en pantalla completa.
  final String? title;
  final VoidCallback? onNext;

  const EngineVideoView({
    super.key,
    required this.model,
    required this.surface,
    required this.phase,
    required this.connectingLabel,
    this.fullscreen = false,
    this.title,
    this.onNext,
  });

  @override
  State<EngineVideoView> createState() => _EngineVideoViewState();
}

class _EngineVideoViewState extends State<EngineVideoView> {
  static const _hideAfter = Duration(seconds: 5);
  static const _skip = Duration(seconds: 10);
  static const _dragSensitivity = 100.0;

  bool _visible = true;
  Timer? _hideTimer;
  Timer? _flashTimer;
  String? _flash;
  double _tapX = 0;
  double _width = 1;
  late double _brightness = currentAppBrightness() ?? 0.5;

  PlaybackModel get _model => widget.model;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _flashTimer?.cancel();
    if (!widget.fullscreen) resetAppBrightness();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleControls() {
    setState(() => _visible = !_visible);
    if (_visible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _showFlash(String text) {
    _flashTimer?.cancel();
    setState(() => _flash = text);
    _flashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  void _skipBy(Duration delta) {
    final target = _model.position + delta;
    final duration = _model.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && target > duration ? duration : target);
    _model.seek(clamped);
    _showFlash(delta.isNegative ? '-10 s' : '+10 s');
  }

  void _onDoubleTap() {
    final third = _width / 3;
    if (_tapX > third && _tapX < _width - third) return;
    _skipBy(_tapX >= _width - third ? _skip : -_skip);
  }

  void _onVerticalDrag(DragUpdateDetails d) {
    final change = -d.delta.dy / _dragSensitivity;
    if (d.localPosition.dx < _width / 2) {
      _brightness = (_brightness + change).clamp(0.0, 1.0);
      setAppBrightness(_brightness);
      _showFlash('Brillo ${(_brightness * 100).round()} %');
    } else {
      final volume = (_model.volume + change).clamp(0.0, 1.0);
      _model.volume = volume;
      _showFlash('Volumen ${(volume * 100).round()} %');
    }
  }

  Future<void> _toggleFullscreen() async {
    if (widget.fullscreen) {
      Navigator.of(context).pop();
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        body: EngineVideoView(
          model: widget.model,
          surface: widget.surface,
          phase: widget.phase,
          connectingLabel: widget.connectingLabel,
          fullscreen: true,
          title: widget.title,
          onNext: widget.onNext,
        ),
      ),
    ));
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _showOptions(String title, List<QualityOption> options, int? active, void Function(int) onPick) {
    _hideTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(title,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            ),
            for (final o in options)
              ListTile(
                dense: true,
                title: Text(o.label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: o.id == active ? AppColors.primary : null)),
                trailing: o.id == active ? const Icon(Icons.check_rounded, color: AppColors.primary) : null,
                onTap: () {
                  onPick(o.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    ).whenComplete(_scheduleHide);
  }

  void _showSpeeds() {
    final current = _model.speed.value;
    _showOptions(
      'VELOCIDAD',
      [for (var i = 0; i < kPlaybackSpeeds.length; i++) QualityOption(i, speedLabel(kPlaybackSpeeds[i]))],
      kPlaybackSpeeds.indexOf(current),
      (i) => _model.setSpeed(kPlaybackSpeeds[i]),
    );
  }

  Widget _round(IconData icon, String tooltip, VoidCallback onPressed, {double size = 34}) {
    return IconButton(
      tooltip: tooltip,
      iconSize: size,
      icon: Icon(icon, color: Colors.white),
      onPressed: () {
        onPressed();
        _scheduleHide();
      },
    );
  }

  Widget _centerControls() {
    return StreamBuilder<bool>(
      stream: _model.bufferingStream,
      initialData: _model.buffering,
      builder: (context, buffering) => ValueListenableBuilder<bool>(
        valueListenable: _model.playing,
        builder: (context, playing, _) {
          // Mientras carga se ve el spinner en este mismo sitio.
          if (buffering.data == true) return const SizedBox.shrink();
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _round(Icons.replay_10_rounded, 'Retroceder 10 segundos', () => _skipBy(-_skip)),
              SizedBox(width: widget.fullscreen ? 48 : 24),
              _round(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                playing ? 'Pausar' : 'Reproducir',
                () => playing ? _model.pause() : _model.play(),
                size: 56,
              ),
              SizedBox(width: widget.fullscreen ? 48 : 24),
              _round(Icons.forward_10_rounded, 'Adelantar 10 segundos', () => _skipBy(_skip)),
            ],
          );
        },
      ),
    );
  }

  /// En pantalla completa, botón con texto; en la vista pequeña, solo el icono.
  Widget _action(IconData icon, String label, VoidCallback onPressed, {String? tooltip}) {
    if (!widget.fullscreen) {
      return IconButton(
        tooltip: tooltip ?? label,
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: 20),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }

  List<Widget> _actions() {
    return [
      ValueListenableBuilder<double>(
        valueListenable: _model.speed,
        builder: (context, speed, _) => _action(Icons.speed_rounded, 'Velocidad (${speedLabel(speed)})',
            _showSpeeds,
            tooltip: 'Velocidad'),
      ),
      ValueListenableBuilder<List<QualityOption>>(
        valueListenable: _model.audioTracks,
        builder: (context, tracks, _) => tracks.length < 2
            ? const SizedBox.shrink()
            : _action(Icons.subtitles_outlined, 'Audio',
                () => _showOptions('AUDIO', tracks, _model.activeAudioTrack, _model.selectAudioTrack)),
      ),
      ValueListenableBuilder<List<QualityOption>>(
        valueListenable: _model.qualities,
        builder: (context, options, _) => options.length < 2
            ? const SizedBox.shrink()
            : _action(Icons.high_quality_rounded, 'Calidad',
                () => _showOptions('CALIDAD', options, _model.activeQuality, _model.selectQuality)),
      ),
      if (widget.onNext != null)
        _action(Icons.skip_next_rounded, 'Siguiente episodio', () {
          if (widget.fullscreen) Navigator.of(context).pop();
          widget.onNext!();
        }),
    ];
  }

  Widget _timeline() {
    return Listener(
      // Mientras se arrastra la barra no deben ocultarse los controles.
      onPointerDown: (_) => _hideTimer?.cancel(),
      onPointerUp: (_) => _scheduleHide(),
      child: TimelineBar(
        position: _model.positionStream,
        currentPosition: () => _model.position,
        duration: () => _model.duration,
        onSeek: _model.seek,
      ),
    );
  }

  Widget _fullscreenButton() => IconButton(
        tooltip: widget.fullscreen ? 'Salir de pantalla completa' : 'Pantalla completa',
        icon: Icon(widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
            color: Colors.white),
        onPressed: _toggleFullscreen,
      );

  Widget _bottom(EdgeInsets inset) {
    if (!widget.fullscreen) {
      return Positioned(
        left: 16,
        right: 4,
        bottom: 0,
        height: 52,
        child: Row(
          children: [
            Expanded(child: _timeline()),
            ..._actions(),
            _fullscreenButton(),
          ],
        ),
      );
    }
    return Positioned(
      left: 24 + inset.left,
      right: 16 + inset.right,
      bottom: 8 + inset.bottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [Expanded(child: _timeline()), _fullscreenButton()]),
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: _actions()),
        ],
      ),
    );
  }

  Widget? _top(EdgeInsets inset) {
    if (!widget.fullscreen || widget.title == null) return null;
    return Positioned(
      top: 8 + inset.top,
      left: 8 + inset.left,
      right: 16 + inset.right,
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: _toggleFullscreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = widget.fullscreen ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
    final top = _top(inset);
    return LayoutBuilder(
      builder: (context, constraints) {
        _width = constraints.maxWidth;
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: Colors.black, child: widget.surface),
            const PlayerWatermark(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              onDoubleTapDown: (d) => _tapX = d.localPosition.dx,
              onDoubleTap: _onDoubleTap,
              onVerticalDragUpdate: _onVerticalDrag,
            ),
            IgnorePointer(
              ignoring: !_visible,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const IgnorePointer(child: ColoredBox(color: Color(0x80000000))),
                    Center(child: _centerControls()),
                    if (top != null) top,
                    _bottom(inset),
                  ],
                ),
              ),
            ),
            PlaybackStatusOverlay(
              buffering: _model.bufferingStream,
              isBuffering: () => _model.buffering,
              phase: widget.phase,
              connectingLabel: widget.connectingLabel,
            ),
            if (_flash != null)
              Positioned(
                top: 16 + inset.top,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(AppRadius.small),
                      ),
                      child: Text(_flash!,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
