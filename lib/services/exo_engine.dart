import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../ui/widgets/engine_video.dart';
import '../ui/widgets/premium_player.dart';

/// HLS o DASH según la URL; `null` deja que ExoPlayer lo detecte. Las URLs del proxy no siempre
/// terminan en `.m3u8`, y sin la pista ExoPlayer las trataría como un archivo normal.
VideoFormat? exoFormatFor(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  if (path.contains('.m3u8') || path.contains('/proxy/hls/')) return VideoFormat.hls;
  if (path.contains('.mpd') || path.contains('/proxy/mpd/')) return VideoFormat.dash;
  return null;
}

/// Motor de video para Android: Media3/ExoPlayer a través de `video_player`.
class ExoEngine implements VideoEngine {
  ExoEngine({this.onLog}) {
    loadAppBrightness();
  }

  final void Function(String)? onLog;
  final _controller = ValueNotifier<VideoPlayerController?>(null);
  final _positions = StreamController<Duration>.broadcast();
  final _bufferingEvents = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  List<VideoAudioTrack> _tracks = const [];
  int _generation = 0;
  bool _buffering = false;
  bool _reportedError = false;
  double _volume = 1;
  Duration _lastPosition = Duration.zero;

  @override
  String get name => 'exoplayer';
  @override
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<double> speed = ValueNotifier<double>(1);
  @override
  final ValueNotifier<List<QualityOption>> qualities = ValueNotifier<List<QualityOption>>(const []);
  @override
  final ValueNotifier<List<QualityOption>> audioTracks = ValueNotifier<List<QualityOption>>(const []);
  @override
  int? activeAudioTrack;
  @override
  int? get activeQuality => null;

  VideoPlayerValue? get _value => _controller.value?.value;

  @override
  Stream<String> get errors => _errors.stream;
  @override
  bool get completed => _value?.isCompleted ?? false;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Duration get position => _value?.position ?? Duration.zero;
  @override
  Duration get duration => _value?.duration ?? Duration.zero;
  @override
  Stream<bool> get bufferingStream => _bufferingEvents.stream;
  @override
  bool get buffering => _buffering;
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    _volume = value;
    _controller.value?.setVolume(value);
  }

  void _setBuffering(bool value) {
    if (value == _buffering) return;
    _buffering = value;
    _bufferingEvents.add(value);
  }

  void _onValue() {
    final v = _value;
    if (v == null) return;
    playing.value = v.isPlaying;
    _setBuffering(v.isBuffering || !v.isInitialized);
    if (v.position != _lastPosition) {
      _lastPosition = v.position;
      _positions.add(v.position);
    }
    if (v.hasError && !_reportedError) {
      _reportedError = true;
      _errors.add(v.errorDescription ?? 'ExoPlayer: error desconocido');
    }
  }

  @override
  Future<void> open(String url, {Duration start = Duration.zero, Map<String, String>? headers}) async {
    final generation = ++_generation;
    _release();
    _reportedError = false;
    _lastPosition = Duration.zero;
    audioTracks.value = const [];
    activeAudioTrack = null;
    _setBuffering(true);

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      formatHint: exoFormatFor(url),
      httpHeaders: headers ?? const {},
    );
    controller.addListener(_onValue);
    _controller.value = controller;
    try {
      await controller.initialize();
      if (generation != _generation) return;
      if (start > Duration.zero) await controller.seekTo(start);
      await controller.setVolume(_volume);
      await controller.setPlaybackSpeed(speed.value);
      await controller.play();
      unawaited(_loadAudioTracks(controller, generation));
    } catch (e) {
      if (generation != _generation) return;
      _setBuffering(false);
      if (!_reportedError) {
        _reportedError = true;
        _errors.add(e.toString());
      }
    }
  }

  Future<void> _loadAudioTracks(VideoPlayerController controller, int generation) async {
    try {
      if (!controller.isAudioTrackSupportAvailable()) return;
      final tracks = await controller.getAudioTracks();
      if (generation != _generation) return;
      _tracks = tracks;
      audioTracks.value = [
        for (var i = 0; i < tracks.length; i++)
          QualityOption(i, tracks[i].label ?? tracks[i].language ?? 'Pista ${i + 1}'),
      ];
      final selected = tracks.indexWhere((t) => t.isSelected);
      activeAudioTrack = selected < 0 ? null : selected;
    } catch (e) {
      onLog?.call('[WARN] exoplayer: no se pudieron leer las pistas de audio');
    }
  }

  void _release() {
    final old = _controller.value;
    if (old == null) return;
    old.removeListener(_onValue);
    _controller.value = null;
    old.dispose();
  }

  @override
  void stop() {
    _generation++;
    _release();
    playing.value = false;
  }

  @override
  void play() => _controller.value?.play();
  @override
  void pause() => _controller.value?.pause();

  @override
  Future<void> seek(Duration position) async {
    await _controller.value?.seekTo(position);
    _positions.add(position);
  }

  @override
  void setSpeed(double value) {
    speed.value = value;
    _controller.value?.setPlaybackSpeed(value);
  }

  @override
  void selectQuality(int id) {}

  @override
  void selectAudioTrack(int id) {
    if (id < 0 || id >= _tracks.length) return;
    activeAudioTrack = id;
    _controller.value?.selectAudioTrack(_tracks[id].id);
  }

  @override
  Widget surface() {
    return ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: _controller,
      builder: (context, controller, _) {
        if (controller == null) return const SizedBox.expand();
        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (!value.isInitialized) return const SizedBox.expand();
            return Center(
              child: AspectRatio(aspectRatio: value.aspectRatio, child: VideoPlayer(controller)),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _generation++;
    _release();
    _positions.close();
    _bufferingEvents.close();
    _errors.close();
    playing.dispose();
    speed.dispose();
    qualities.dispose();
    audioTracks.dispose();
    _controller.dispose();
  }
}
