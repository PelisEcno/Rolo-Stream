import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/mdk.dart' as mdk;
import '../theme/app_theme.dart';

/// Mide si un salto de verdad terminó en reproducción.
class SeekProbe {
  final Duration target;
  final DateTime startedAt;
  SeekProbe(this.target, this.startedAt);

  /// Un salto por fotograma clave puede caer bastante antes del punto pedido.
  static const _landingMargin = Duration(seconds: 30);
  static const _advanced = Duration(seconds: 1);
  static const _stuckAfter = Duration(seconds: 15);

  Duration? _landedAt;

  /// `null` mientras no se sabe. Si no, el texto con el resultado.
  String? update(Duration position, DateTime now) {
    final elapsed = now.difference(startedAt);
    final landed = _landedAt;
    final near = (position - target).abs() <= _landingMargin;
    if (landed == null) {
      if (near) _landedAt = position;
    } else if (near && position - landed >= _advanced) {
      return 'OK: reproduce en ${position.inSeconds}s, ${elapsed.inMilliseconds} ms tras pedir '
          '${target.inSeconds}s';
    }
    if (elapsed >= _stuckAfter) {
      return 'CLAVADO: en ${position.inSeconds}s tras ${elapsed.inSeconds}s pidiendo '
          '${target.inSeconds}s';
    }
    return null;
  }
}

/// Prueba de otro motor de video (`fvp`/libmdk) con el mismo stream, sin controles definitivos.
/// Solo se llega desde la consola de depuración. Sirve para decidir si conviene migrar.
class FvpTestScreen extends StatefulWidget {
  final String url;
  final Duration savedPosition;
  const FvpTestScreen({super.key, required this.url, required this.savedPosition});

  @override
  State<FvpTestScreen> createState() => _FvpTestScreenState();
}

class _FvpTestScreenState extends State<FvpTestScreen> {
  final _player = mdk.Player();
  final _lines = <String>[];
  Timer? _timer;
  SeekProbe? _probe;
  Duration _position = Duration.zero;
  int _duration = 0;
  String _lastEvent = '';

  Duration get _target =>
      widget.savedPosition > Duration.zero ? widget.savedPosition : const Duration(seconds: 526);

  void _log(String text) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (!mounted) return;
    setState(() {
      _lines.insert(0, '${two(t.hour)}:${two(t.minute)}:${two(t.second)} $text');
      if (_lines.length > 200) _lines.removeLast();
    });
  }

  @override
  void initState() {
    super.initState();
    _log('Motor: fvp/libmdk ${mdk.version()}');
    // Hardware si lo hay; si no, software: es lo que necesita AV1 en la mayoría de iPhones.
    _player.setDecoders(mdk.MediaType.video, const ['VT', 'dav1d', 'FFmpeg']);
    _player.onMediaStatus.listen((e) => _log('Estado: ${e.newValue}'));
    _player.onStateChanged.listen((e) => _log('Reproducción: ${e.newValue.name}'));
    _player.onEvent.listen((e) {
      // Los avances de buffer llegan a decenas por segundo y no dicen nada aquí.
      if (e.category == 'reader.buffering') return;
      final text = '${e.category} ${e.error} ${e.detail}';
      if (text != _lastEvent) _log('Evento: $text');
      _lastEvent = text;
    });
    _player.media = widget.url;
    _player.updateTexture();
    _player.state = mdk.PlaybackState.playing;
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    final position = Duration(milliseconds: _player.position);
    final info = _player.mediaInfo;
    if (info.duration != _duration) {
      _duration = info.duration;
      final videos = info.video;
      _log('Duración: ${_duration ~/ 1000}s. '
          'Video: ${videos == null || videos.isEmpty ? 'sin pista' : videos.first.codec.codec}');
    }
    final result = _probe?.update(position, DateTime.now());
    if (result != null) {
      _probe = null;
      _log(result);
    }
    setState(() => _position = position);
  }

  void _seek(Duration target) {
    final clamped = target < Duration.zero ? Duration.zero : target;
    _log('Salto pedido a ${clamped.inSeconds}s');
    _probe = SeekProbe(clamped, DateTime.now());
    _player.seek(position: clamped.inMilliseconds);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _player.dispose();
    super.dispose();
  }

  Widget _button(String label, VoidCallback onPressed) =>
      OutlinedButton(onPressed: onPressed, child: Text(label));

  @override
  Widget build(BuildContext context) {
    final playing = _player.state == mdk.PlaybackState.playing;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba de fvp'),
        actions: [
          IconButton(
            tooltip: 'Copiar registro',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => Clipboard.setData(ClipboardData(text: _lines.reversed.join('\n'))),
          ),
        ],
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(
              color: Colors.black,
              child: ValueListenableBuilder<int?>(
                valueListenable: _player.textureId,
                builder: (_, id, __) => id == null
                    ? const Center(child: CircularProgressIndicator())
                    : Texture(textureId: id),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('${_position.inSeconds}s de ${_duration ~/ 1000}s',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _button('Saltar a ${_target.inSeconds}s', () => _seek(_target)),
              _button('+5 min', () => _seek(_position + const Duration(minutes: 5))),
              _button('-5 min', () => _seek(_position - const Duration(minutes: 5))),
              _button(playing ? 'Pausar' : 'Seguir', () {
                _player.state = playing ? mdk.PlaybackState.paused : mdk.PlaybackState.playing;
              }),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _lines.length,
              itemBuilder: (_, i) => Text(_lines[i],
                  style: const TextStyle(
                      fontSize: 11, fontFamily: 'monospace', color: AppColors.textMuted)),
            ),
          ),
        ],
      ),
    );
  }
}
