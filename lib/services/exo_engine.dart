import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ui/widgets/engine_video.dart';
import '../ui/widgets/premium_player.dart';

/// `hls` o `dash` según la URL; `null` deja que ExoPlayer lo detecte. Las URLs del proxy no siempre
/// terminan en `.m3u8`, y sin la pista ExoPlayer las trataría como un archivo normal.
String? exoFormatFor(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  if (path.contains('.m3u8') || path.contains('/proxy/hls/')) return 'hls';
  if (path.contains('.mpd') || path.contains('/proxy/mpd/')) return 'dash';
  return null;
}

const _methods = MethodChannel('com.rolostream/exo');
final Stream<Map<Object?, Object?>> _events = const EventChannel('com.rolostream/exo/events')
    .receiveBroadcastStream()
    .cast<Map<Object?, Object?>>();

/// Motor de video para Android: Media3/ExoPlayer nativo (`NativeVideoPlayer.kt`) dibujado en una
/// textura. Los controles los pone Flutter.
class ExoEngine implements VideoEngine {
  ExoEngine({this.onLog}) {
    loadAppBrightness();
    _subscription = _events.listen(_onEvent);
    _ready = _methods.invokeMethod<int>('create').then((id) => _textureId.value = id);
  }

  final void Function(String)? onLog;
  late final StreamSubscription<Map<Object?, Object?>> _subscription;
  late final Future<int?> _ready;
  final _textureId = ValueNotifier<int?>(null);
  final _aspect = ValueNotifier<double?>(null);
  final _positions = StreamController<Duration>.broadcast();
  final _bufferingEvents = StreamController<bool>.broadcast();
  final _errors = StreamController<String>.broadcast();
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _buffering = false;
  bool _completed = false;
  bool _disposed = false;
  double _volume = 1;
  int? _activeQuality;

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
  int? get activeQuality => _activeQuality;

  @override
  Stream<String> get errors => _errors.stream;
  @override
  bool get completed => _completed;
  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Duration get position => _position;
  @override
  Duration get duration => _duration;
  @override
  Stream<bool> get bufferingStream => _bufferingEvents.stream;
  @override
  bool get buffering => _buffering;
  @override
  double get volume => _volume;
  @override
  set volume(double value) {
    _volume = value;
    _call('volume', {'value': value});
  }

  Future<void> _call(String method, [Map<String, Object?> args = const {}]) async {
    final id = await _ready;
    if (id == null || _disposed) return;
    await _methods.invokeMethod<void>(method, {'id': id, ...args});
  }

  void _setBuffering(bool value) {
    if (value == _buffering) return;
    _buffering = value;
    _bufferingEvents.add(value);
  }

  void _onEvent(Map<Object?, Object?> e) {
    if (_disposed || e['id'] != _textureId.value) return;
    switch (e['type']) {
      case 'position':
        final position = Duration(milliseconds: e['position'] as int);
        _duration = Duration(milliseconds: e['duration'] as int);
        if (position != _position) {
          _position = position;
          _positions.add(position);
        }
      case 'state':
        _setBuffering(e['buffering'] as bool);
        _completed = e['ended'] as bool;
      case 'playing':
        playing.value = e['value'] as bool;
      case 'size':
        _aspect.value = (e['aspect'] as num).toDouble();
      case 'firstFrame':
        onLog?.call('[INFO] exoplayer: primer fotograma');
      case 'error':
        _setBuffering(false);
        _errors.add(e['message'] as String);
      case 'tracks':
        final audio = (e['audio'] as List).cast<String>();
        audioTracks.value = [for (var i = 0; i < audio.length; i++) QualityOption(i, audio[i])];
        final audioSelected = e['audioSelected'] as int;
        activeAudioTrack = audioSelected < 0 ? null : audioSelected;
        final labels = (e['qualities'] as List).cast<String>();
        qualities.value = labels.length < 2
            ? const []
            : [const QualityOption(-1, 'Auto'), for (var i = 0; i < labels.length; i++) QualityOption(i, labels[i])];
        final qualitySelected = e['qualitySelected'] as int;
        _activeQuality ??= qualitySelected;
    }
  }

  @override
  Future<void> open(String url, {Duration start = Duration.zero, Map<String, String>? headers}) async {
    _completed = false;
    _position = start;
    _duration = Duration.zero;
    _activeQuality = null;
    activeAudioTrack = null;
    audioTracks.value = const [];
    qualities.value = const [];
    _setBuffering(true);
    await _call('speed', {'value': speed.value});
    await _call('volume', {'value': _volume});
    await _call('open', {
      'url': url,
      'headers': headers ?? const <String, String>{},
      'startMs': start.inMilliseconds,
      'format': exoFormatFor(url),
    });
  }

  @override
  void stop() {
    playing.value = false;
    _call('stop');
  }

  @override
  void play() => _call('play');
  @override
  void pause() => _call('pause');

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positions.add(position);
    await _call('seek', {'ms': position.inMilliseconds});
  }

  @override
  void setSpeed(double value) {
    speed.value = value;
    _call('speed', {'value': value});
  }

  @override
  void selectQuality(int id) {
    _activeQuality = id;
    _call('quality', {'index': id});
  }

  @override
  void selectAudioTrack(int id) {
    activeAudioTrack = id;
    _call('audio', {'index': id});
  }

  @override
  Widget surface() {
    return ValueListenableBuilder<int?>(
      valueListenable: _textureId,
      builder: (context, id, _) {
        if (id == null) return const SizedBox.expand();
        return ValueListenableBuilder<double?>(
          valueListenable: _aspect,
          builder: (context, ratio, _) => Center(
            child: AspectRatio(aspectRatio: ratio ?? 16 / 9, child: Texture(textureId: id)),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _ready.then((id) {
      if (id != null) _methods.invokeMethod<void>('dispose', {'id': id});
    });
    _subscription.cancel();
    _positions.close();
    _bufferingEvents.close();
    _errors.close();
    playing.dispose();
    speed.dispose();
    qualities.dispose();
    audioTracks.dispose();
    _textureId.dispose();
    _aspect.dispose();
  }
}
