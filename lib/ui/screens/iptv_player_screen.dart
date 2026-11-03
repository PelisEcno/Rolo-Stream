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

  Media get _media => Media(widget.channel.url,
      httpHeaders: widget.channel.headers.isEmpty ? null : widget.channel.headers);

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _watchdog.dispose();
    _player.dispose();
    super.dispose();
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
