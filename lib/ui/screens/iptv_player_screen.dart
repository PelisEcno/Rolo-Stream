import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../iptv/iptv_models.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_player.dart';

/// Reproductor de un canal IPTV. Abre la URL tal cual (HLS, MPEG-TS, MP4…) con `media_kit`.
///
/// En los directos no hay duración: la barra de progreso se oculta y no hay nada que "buscar".
/// En las películas y series de la lista (`.mkv`, `.mp4`) la barra aparece en cuanto se conoce
/// la duración.
class IPTVPlayerScreen extends StatefulWidget {
  final Channel channel;
  const IPTVPlayerScreen({super.key, required this.channel});

  @override
  State<IPTVPlayerScreen> createState() => _IPTVPlayerScreenState();
}

class _IPTVPlayerScreenState extends State<IPTVPlayerScreen> {
  late final Player _player = createPremiumPlayer();
  late final VideoController _controller = VideoController(_player);
  final _subs = <StreamSubscription<dynamic>>[];

  late final StallRecovery _recovery = StallRecovery(
    _player,
    reopen: (at) => StallRecovery.reopenAt(_player, _media, at),
    onGiveUp: () {
      if (mounted) setState(() => _error = _friendlyError);
    },
  );

  Timer? _errorTimer;
  String? _error;

  Media get _media => Media(widget.channel.url,
      httpHeaders: widget.channel.headers.isEmpty ? null : widget.channel.headers);

  @override
  void initState() {
    super.initState();
    _subs.add(_player.stream.error.listen(_onError));
    _recovery; // empieza a vigilar el buffer
    _open();
  }

  @override
  void dispose() {
    _errorTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _recovery.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    _errorTimer?.cancel();
    setState(() => _error = null);
    try {
      await _player.open(_media);
    } catch (_) {
      if (mounted) setState(() => _error = _friendlyError);
    }
  }

  static const _friendlyError =
      'No se pudo reproducir este canal. Puede estar caído o no estar disponible ahora.';

  /// mpv emite errores transitorios aunque el video siga: solo se avisa si, pasados 2 s,
  /// la reproducción no avanza.
  void _onError(String message) {
    if (message.isEmpty) return;
    final posAtError = _player.state.position;
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final advanced = _player.state.playing &&
          _player.state.position - posAtError > const Duration(milliseconds: 500);
      if (!advanced) setState(() => _error = _friendlyError);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.channel;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(c.grupo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
      ),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                PremiumVideo(
                    player: _player,
                    controller: _controller,
                    reconnecting: _recovery.reconnecting),
                if (_error != null)
                  Container(
                    color: Colors.black87,
                    padding: const EdgeInsets.all(16),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: AppColors.textMuted, size: 36),
                        const SizedBox(height: 8),
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _open,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('REINTENTAR'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
