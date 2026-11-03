import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'premium_player.dart';

/// Una calidad elegible del stream.
class QualityOption {
  final int id;
  final String label;
  const QualityOption(this.id, this.label);
}

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
  ValueListenable<List<QualityOption>> get qualities;
  int? get activeQuality;
  void selectQuality(int id);
  void play();
  void pause();
  Future<void> seek(Duration position);
}

/// Video con controles del mismo estilo que [PremiumVideo], para motores que no son `media_kit`:
/// marca de agua, doble toque ±10 s, deslizar para volumen y brillo, calidad y pantalla completa.
class EngineVideoView extends StatefulWidget {
  final PlaybackModel model;
  final Widget surface;
  final ValueListenable<PlaybackPhase> phase;
  final String connectingLabel;
  final bool fullscreen;

  const EngineVideoView({
    super.key,
    required this.model,
    required this.surface,
    required this.phase,
    required this.connectingLabel,
    this.fullscreen = false,
  });

  @override
  State<EngineVideoView> createState() => _EngineVideoViewState();
}

class _EngineVideoViewState extends State<EngineVideoView> {
  static const _hideAfter = Duration(seconds: 5);
  static const _doubleTapSeek = Duration(seconds: 10);
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

  void _onDoubleTap() {
    final third = _width / 3;
    if (_tapX > third && _tapX < _width - third) return;
    final forward = _tapX >= _width - third;
    final target = _model.position + (forward ? _doubleTapSeek : -_doubleTapSeek);
    final duration = _model.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (duration > Duration.zero && target > duration ? duration : target);
    _model.seek(clamped);
    _showFlash(forward ? '+10 s' : '-10 s');
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
        ),
      ),
    ));
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _showQualities(List<QualityOption> options) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text('CALIDAD',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            ),
            for (final o in options)
              ListTile(
                dense: true,
                title: Text(o.label,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: o.id == _model.activeQuality ? AppColors.primary : null)),
                trailing: o.id == _model.activeQuality
                    ? const Icon(Icons.check_rounded, color: AppColors.primary)
                    : null,
                onTap: () {
                  _model.selectQuality(o.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _centerButton() {
    return StreamBuilder<bool>(
      stream: _model.bufferingStream,
      initialData: _model.buffering,
      builder: (context, buffering) => ValueListenableBuilder<bool>(
        valueListenable: _model.playing,
        builder: (context, playing, _) {
          // Mientras carga se ve el spinner en este mismo sitio.
          if (buffering.data == true) return const SizedBox.shrink();
          return IconButton(
            tooltip: playing ? 'Pausar' : 'Reproducir',
            iconSize: 56,
            icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white),
            onPressed: () {
              playing ? _model.pause() : _model.play();
              _scheduleHide();
            },
          );
        },
      ),
    );
  }

  Widget _bottomBar() {
    return Listener(
      // Mientras se arrastra la barra no deben ocultarse los controles.
      onPointerDown: (_) => _hideTimer?.cancel(),
      onPointerUp: (_) => _scheduleHide(),
      child: Row(
        children: [
          Expanded(
            child: TimelineBar(
              position: _model.positionStream,
              currentPosition: () => _model.position,
              duration: () => _model.duration,
              onSeek: _model.seek,
            ),
          ),
          ValueListenableBuilder<List<QualityOption>>(
            valueListenable: _model.qualities,
            builder: (context, options, _) => options.length < 2
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Calidad',
                    icon: const Icon(Icons.high_quality_rounded, color: Colors.white),
                    onPressed: () => _showQualities(options),
                  ),
          ),
          IconButton(
            tooltip: widget.fullscreen ? 'Salir de pantalla completa' : 'Pantalla completa',
            icon: Icon(widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                color: Colors.white),
            onPressed: _toggleFullscreen,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = widget.fullscreen ? MediaQuery.paddingOf(context) : EdgeInsets.zero;
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
                    const IgnorePointer(child: ColoredBox(color: Color(0x66000000))),
                    Center(child: _centerButton()),
                    Positioned(
                      left: 16 + inset.left,
                      right: 8 + inset.right,
                      bottom: widget.fullscreen ? 12 + inset.bottom : 0,
                      height: 56,
                      child: _bottomBar(),
                    ),
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
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
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
