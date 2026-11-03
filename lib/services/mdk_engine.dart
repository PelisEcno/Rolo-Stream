import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import '../ui/widgets/engine_video.dart';
import '../ui/widgets/premium_player.dart';

/// Motor de video basado en `fvp`/libmdk.
///
/// Se usa con los servidores donde FFmpeg, dentro de `media_kit`, se queda clavado al saltar a un
/// segmento sin cargar. Decodifica AV1 por software con `dav1d` en los iPhone sin hardware para ello.
class MdkEngine implements PlaybackModel {
  MdkEngine({this.onLog}) {
    loadAppBrightness();
    final decoders = switch (defaultTargetPlatform) {
      TargetPlatform.iOS || TargetPlatform.macOS => const ['VT', 'dav1d', 'FFmpeg'],
      TargetPlatform.android => const ['AMediaCodec', 'dav1d', 'FFmpeg'],
      _ => const ['dav1d', 'FFmpeg'],
    };
    _player.setDecoders(mdk.MediaType.video, decoders);
    _player.onStateChanged.listen((e) {
      playing.value = e.newValue == mdk.PlaybackState.playing;
    });
    _player.onMediaStatus.listen((e) => _onStatus(e.newValue));
    _player.onEvent.listen((e) {
      if (e.category == 'decoder.video' && e.error == 0) onLog?.call('[INFO] fvp: decodifica con ${e.detail}');
    });
  }

  final void Function(String)? onLog;
  final _player = mdk.Player();
  final _positions = StreamController<Duration>.broadcast();
  final _bufferingEvents = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  Timer? _ticker;
  bool _buffering = false;
  bool _completed = false;
  bool _disposed = false;

  /// El proxy o el servidor no pudieron abrir el video.
  Stream<String> get errors => _errors.stream;
  bool get completed => _completed;

  /// Relación de aspecto del video, cuando ya se conoce.
  final aspectRatio = ValueNotifier<double?>(null);

  @override
  final ValueNotifier<bool> playing = ValueNotifier<bool>(false);
  @override
  final ValueNotifier<List<QualityOption>> qualities = ValueNotifier<List<QualityOption>>(const []);
  int? _activeQuality;
  @override
  int? get activeQuality => _activeQuality;

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Duration get position => Duration(milliseconds: _player.position);
  @override
  Duration get duration => Duration(milliseconds: _player.mediaInfo.duration);
  @override
  Stream<bool> get bufferingStream => _bufferingEvents.stream;
  @override
  bool get buffering => _buffering;
  @override
  double get volume => _player.volume;
  @override
  set volume(double value) => _player.volume = value;

  void _onStatus(mdk.MediaStatus status) {
    final buffering = status.test(mdk.MediaStatus.loading) ||
        status.test(mdk.MediaStatus.buffering) ||
        status.test(mdk.MediaStatus.seeking);
    if (buffering != _buffering) {
      _buffering = buffering;
      _bufferingEvents.add(buffering);
    }
    _completed = status.test(mdk.MediaStatus.end);
    if (status.test(mdk.MediaStatus.invalid)) _errors.add('Failed to open: fvp invalid media');
    if (status.test(mdk.MediaStatus.loaded)) _readTracks();
  }

  void _readTracks() {
    final videos = _player.mediaInfo.video ?? const [];
    if (videos.isEmpty) return;
    final codec = videos.first.codec;
    if (codec.width > 0 && codec.height > 0) aspectRatio.value = codec.width / codec.height;
    qualities.value = [
      for (var i = 0; i < videos.length; i++)
        QualityOption(i, videos[i].codec.height > 0 ? '${videos[i].codec.height}p' : 'Pista ${i + 1}'),
    ];
    _activeQuality ??= videos.isEmpty ? null : 0;
  }

  /// Abre [url] en [start], sin pasar por el principio del video.
  Future<void> open(String url, {Duration start = Duration.zero}) async {
    _completed = false;
    _activeQuality = null;
    _player.state = mdk.PlaybackState.stopped;
    _player.media = url;
    unawaited(_player.updateTexture().catchError((Object _) => -1));
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!_disposed && playing.value) _positions.add(position);
    });
    if (start > Duration.zero) {
      final result = await _player
          .prepare(position: start.inMilliseconds)
          .timeout(const Duration(seconds: 20), onTimeout: () => -1);
      if (_disposed) return;
      if (result < 0) onLog?.call('[WARN] fvp: no se pudo preparar en ${start.inSeconds}s ($result)');
    }
    _player.state = mdk.PlaybackState.playing;
  }

  void stop() {
    _ticker?.cancel();
    _player.state = mdk.PlaybackState.stopped;
  }

  @override
  void play() => _player.state = mdk.PlaybackState.playing;
  @override
  void pause() => _player.state = mdk.PlaybackState.paused;

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position: position.inMilliseconds);
    if (!_disposed) _positions.add(this.position);
  }

  @override
  void selectQuality(int id) {
    _activeQuality = id;
    _player.setActiveTracks(mdk.MediaType.video, [id]);
  }

  /// Imagen del video, centrada y sin deformar.
  Widget surface() {
    return ValueListenableBuilder<int?>(
      valueListenable: _player.textureId,
      builder: (context, id, _) {
        if (id == null) return const SizedBox.expand();
        return ValueListenableBuilder<double?>(
          valueListenable: aspectRatio,
          builder: (context, ratio, _) => Center(
            child: AspectRatio(aspectRatio: ratio ?? 16 / 9, child: Texture(textureId: id)),
          ),
        );
      },
    );
  }

  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _player.dispose();
    _positions.close();
    _bufferingEvents.close();
    _errors.close();
    playing.dispose();
    qualities.dispose();
    aspectRatio.dispose();
  }
}
