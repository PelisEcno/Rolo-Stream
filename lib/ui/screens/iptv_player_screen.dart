import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../iptv/iptv_models.dart';
import '../theme/app_theme.dart';
import '../widgets/premium_player.dart';

/// Reproductor de un canal IPTV. Abre la URL tal cual (HLS, MPEG-TS, MP4…) con `media_kit`.
///
/// Los directos no tienen barra de progreso ni se pueden pausar. Las películas y series de la
/// lista (`.mkv`, `.mp4`) tienen los controles normales: ver [Channel.isLive].
class IPTVPlayerScreen extends StatefulWidget {
  final Channel channel;
  const IPTVPlayerScreen({super.key, required this.channel});

  @override
  State<IPTVPlayerScreen> createState() => _IPTVPlayerScreenState();
}

class _IPTVPlayerScreenState extends State<IPTVPlayerScreen> {
  late final Player _player = createPremiumPlayer();
  late final VideoController _controller = createPremiumController(_player);
  late final PlaybackWatchdog _watchdog = PlaybackWatchdog(
    _player,
    // En un directo no hay posición a la que volver.
    reopen: (at) => widget.channel.isLive == true
        ? _player.open(_media)
        : reopenAt(_player, _media, at),
    onGiveUp: () {
      if (mounted) setState(() => _error = _friendlyError);
    },
  );

  String? _error;
  StreamSubscription<Tracks>? _tracksSub;
  StreamSubscription<bool>? _playingSub;
  Timer? _resumeTimer;

  bool get _isLiveNow => widget.channel.isLive ?? (_player.state.duration == Duration.zero);

  Media get _media => Media(widget.channel.url,
      httpHeaders: widget.channel.headers.isEmpty ? null : widget.channel.headers);

  @override
  void initState() {
    super.initState();
    _tracksSub = _player.stream.tracks.listen(_ensureLiveAudio);
    _playingSub = _player.stream.playing.listen(_keepLivePlaying);
    // Antes de abrir: `Player.open` solo espera al controlador si ya existe. Sin él, abre el canal y
    // el controlador llega después a reiniciar la salida de video con el canal ya en marcha.
    _controller;
    _open();
  }

  @override
  void dispose() {
    _tracksSub?.cancel();
    _playingSub?.cancel();
    _resumeTimer?.cancel();
    _watchdog.dispose();
    _player.dispose();
    super.dispose();
  }

  /// Un directo no tiene botón de pausa: si se detiene, no lo pidió nadie. Se espera un momento porque
  /// `Player.open` pasa por pausa cada vez que abre.
  void _keepLivePlaying(bool playing) {
    _resumeTimer?.cancel();
    if (playing || !_isLiveNow) return;
    _resumeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _error == null && !_player.state.playing) _player.play();
    });
  }

  /// En un directo se fija la pista de audio en cuanto mpv conoce las pistas (también al reabrir).
  void _ensureLiveAudio(Tracks tracks) {
    if (!_isLiveNow) return;
    final track = liveAudioTrackToForce(tracks, _player.state.track);
    if (track != null) _player.setAudioTrack(track);
  }

  /// Los errores de mpv no se muestran: suelen ser transitorios. Si el canal de verdad no
  /// arranca, lo dice [PlaybackWatchdog] al agotar los reintentos.
  Future<void> _open() async {
    setState(() => _error = null);
    _watchdog.begin();
    try {
      await _player.open(_media);
    } catch (_) {
      _watchdog.stop();
      if (mounted) setState(() => _error = _friendlyError);
    }
  }

  static const _friendlyError =
      'No se pudo reproducir este canal. Puede estar caído o no estar disponible ahora.';

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
                  phase: _watchdog.phase,
                  live: c.isLive,
                  connectingLabel: 'Conectando al canal...',
                ),
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
