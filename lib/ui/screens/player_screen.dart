import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:rolostream_core/rolostream_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_error.dart';
import '../../services/mediaflow_service.dart';
import '../../services/source_registry.dart';
import '../../services/watch_progress_service.dart';
import '../theme/app_theme.dart';
import '../utils/episode_label.dart';
import '../widgets/anime_card.dart';
import '../widgets/debug_console.dart';
import '../widgets/premium_player.dart';

class PlayerScreen extends StatefulWidget {
  final String slug;
  final int numero;
  final String animeTitulo;

  /// Carátula para la tarjeta de "Seguir viendo".
  final String imagen;

  /// Fuente del episodio; si es null se usa la activa.
  final String? sourceId;

  const PlayerScreen({
    super.key,
    required this.slug,
    required this.numero,
    required this.animeTitulo,
    this.imagen = '',
    this.sourceId,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final SourcePlugin _source =
      pluginRegistry.byId(widget.sourceId ?? '') ?? pluginRegistry.active;
  // `warn` deja pasar los avisos de FFmpeg/mpv (hls, tcp, http…) a la consola de depuración.
  late final Player _player = createPremiumPlayer(logLevel: MPVLogLevel.warn);
  late final VideoController _controller = createPremiumController(_player);
  late final PlaybackWatchdog _watchdog = PlaybackWatchdog(
    _player,
    reopen: (at) async {
      _log.add('[WARN] El video no avanza: se reabre en ${at.inSeconds}s');
      // Si aún no se llegó al punto guardado, `at` es anterior a él.
      await reopenAt(_player, _media!, at > _resume ? at : _resume);
    },
    onGiveUp: () {
      if (!mounted) return;
      _errorShownAt = _player.state.position; // el aviso se quita solo si el video vuelve a avanzar
      setState(() => _playError = 'Se perdió la conexión con el servidor');
    },
  );
  Media? _media;

  /// Dónde abrir el video: lo guardado al entrar y, después, por dónde va (también al cambiar de
  /// servidor).
  late Duration _resume = WatchProgressService.instance
          .resumePoint(_source.id, widget.slug, widget.numero) ??
      Duration.zero;
  Timer? _progressTimer;
  ResumeGuard _guard = ResumeGuard(Duration.zero);
  bool _durationLogged = false;

  List<VideoServer> _servers = [];
  int _selected = 0;
  bool _loading = true;
  bool _opening = false;
  String? _error;
  String? _playError;

  Timer? _errorTimer;
  Duration? _errorShownAt;

  final _log = DebugLog();
  bool _showConsole = false;

  @override
  void initState() {
    super.initState();
    _player.stream.error.listen(_onPlayerError);
    _player.stream.log.listen((l) {
      // media_kit intenta fijar `osc`, que no existe en el libmpv móvil: es inofensivo.
      if (l.prefix == 'media_kit' && l.text.contains('_setProperty(osc')) return;
      final tag = l.level == 'error' || l.level == 'fatal' ? '[PLAYER]' : '[WARN]';
      _log.add('$tag mpv ${l.prefix}: ${DebugLog.short(l.text, 220)}');
    });
    // Si el video avanza después de un error, el error era transitorio: quitamos el aviso.
    _player.stream.position.listen((pos) {
      final at = _errorShownAt;
      if (_playError != null &&
          at != null &&
          _player.state.playing &&
          pos - at > const Duration(seconds: 1)) {
        _errorShownAt = null;
        _watchdog.begin();
        if (mounted) setState(() => _playError = null);
      }
    });
    _player.stream.position.listen(_verifyResume);
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
    _load();
  }

  /// Con el video ya avanzando, salta al punto guardado si `Media.start` no se cumplió.
  void _verifyResume(Duration position) {
    if (_watchdog.phase.value != PlaybackPhase.playing) return;
    final duration = _player.state.duration;
    if (!_durationLogged) {
      _durationLogged = true;
      _log.add(duration > Duration.zero
          ? '[INFO] Duración: ${duration.inSeconds}s, arranca en ${position.inSeconds}s'
          : '[WARN] El servidor no informa la duración: no se puede guardar ni reanudar');
    }
    if (duration <= Duration.zero) return;

    final jump = _guard.check(position, DateTime.now());
    if (jump != null) {
      _log.add('[WARN] Arrancó en ${position.inSeconds}s en vez de ${jump.inSeconds}s: '
          'se salta (intento ${_guard.seeks})');
      _player.seek(jump);
    } else if (_guard.gaveUp) {
      _guard.gaveUp = false;
      _log.add('[WARN] Este servidor no permitió saltar a ${_guard.target.inSeconds}s');
    }
  }

  void _saveProgress() {
    // Solo con el video avanzando: al abrir o reabrir, la posición pasa un momento por 0.
    if (_watchdog.phase.value != PlaybackPhase.playing) return;
    if (!_guard.done) return;
    final position = _player.state.position;
    if (position == _resume) return;
    _resume = position;
    WatchProgressService.instance.save(
      sourceId: _source.id,
      slug: widget.slug,
      numero: widget.numero,
      titulo: widget.animeTitulo,
      imagen: widget.imagen,
      position: position,
      duration: _player.state.duration,
    );
  }

  /// Con errores transitorios (un segmento que falla y se reintenta) el video
  /// sigue sonando: esperamos un momento y solo avisamos si dejó de avanzar.
  void _onPlayerError(String e) {
    if (e.isEmpty) return;
    _log.add('[PLAYER] ${DebugLog.short(e, 300)}');
    final posAtError = _player.state.position;
    _errorTimer?.cancel();
    _errorTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final advanced = _player.state.playing &&
          _player.state.position - posAtError > const Duration(milliseconds: 500);
      if (advanced) {
        _log.add('[WARN] Error transitorio, la reproducción continúa');
        return;
      }
      // Un servidor que da error no se reintenta: el usuario puede elegir otro.
      _watchdog.stop();
      setState(() {
        _playError = e;
        _errorShownAt = _player.state.position;
      });
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _saveProgress();
    _errorTimer?.cancel();
    _watchdog.dispose();
    _log.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final servers = await _source.getServers(widget.slug, widget.numero);
      if (!mounted) return;
      setState(() => _servers = servers);
      if (servers.isNotEmpty) await _select(0);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// El proxy no reconoce algunos alias de los servidores: se traducen aquí.
  /// El resto se envía tal cual (en minúsculas).
  String _mapServerNameToProxyHost(String serverName) {
    // Algunas fuentes anotan el idioma: "Voe (Latino)" → "voe".
    final name = serverName.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '').trim().toLowerCase();
    switch (name) {
      // --- Latanime ---
      case 'dsvplay':
      case 'playmogo':
        return 'doodstream';
      case 'lulu':
        return 'lulustream';

      // --- AnimeAV1 (el proxy ya los reconoce con el mismo nombre) ---
      case 'voe':
      case 'byse':
      case 'mp4upload':
      case 'yourupload': // TioAnime / AnimedLatino: extractor `yourupload` del proxy (mp4 directo)
        return name;

      // --- JKAnime: el proxy reconoce estos con el mismo nombre ---
      //   voe, filemoon, mixdrop, mp4upload, streamtape, doodstream (caen en `default`).
      //   streamwish, vidhide: sin confirmar con el proxy (se envían tal cual).
      //   mega, mediafire: son descargas, no embeds reproducibles.

      // --- Cuevana: filemoon y doodstream caen en `default`. Los hosts .lol (Hyper/Nebula)
      //   los resuelve el extractor streamwish del proxy.
      //   vsembed, vidlink, videasy, vidapi: sin extractor que funcione (403/404).
      case 'vidhide':
      case 'nebula':
      case 'streamwish':
        return 'streamwish';

      // --- PelisPlusHD: streamwish / vidhide (arriba), doodstream, voe, filemoon y mp4upload
      //   caen en `default`. Sin extractor: sbfast, vip, netu, upfast.

      // --- TioAnime: voe y yourupload (arriba) y okru (`default`) los extrae el proxy.
      //   Sin extractor: mega, streamsb, vidguard, maru, netu. mixdrop usa el dominio mixdroop.bz.

      // --- AnimedLatino: okru y voe caen en `default` y el proxy los extrae. Sin extractor:
      //   mega, yourupload, streamsb, vidguard, maru (my.mail.ru), netu (hqq.tv), youtube.

      // --- AnimeAV1: player.zilla-networks.com; el proxy lo registra como `zilla` ---
      case 'hls':
      case 'zilla':
        return 'zilla';

      // --- AnimeAV1: pendientes de confirmar con el proxy ---
      // case 'upnshare':
      //   return '...';
      // case 'yourupload':
      //   return '...';
      // case 'streamtape':
      //   return '...';

      default:
        return name;
    }
  }

  /// Mensaje corto para el usuario; el error crudo queda en la consola de depuración.
  String _friendlyPlayerError(String raw) => AppError.from(raw).message;

  /// Obtiene la URL real del video y los headers que el servidor exige
  /// (Referer, User-Agent) a través del proxy.
  /// Si el proxy no responde o falla, devuelve la URL directa sin headers.
  ///
  /// `streamUrl` es el `mediaflow_proxy_url` del JSON, si lo trae: el manifiesto y los
  /// segmentos pasan por el proxy, que les pone los headers (los CDN que exigen
  /// cabeceras en cada segmento devuelven 403 si FFmpeg los pide directo).
  Future<({String url, Map<String, String>? headers, String? streamUrl, String host})>
      _getProxiedUrl(VideoServer server) async {
    final direct = (
      url: server.url,
      headers: null as Map<String, String>?,
      streamUrl: null as String?,
      host: _mapServerNameToProxyHost(server.nombre),
    );
    if (!await MediaFlowService.isRunning() && mounted) {
      _log.add('[WARN] Proxy no responde en :${MediaFlowService.port}, se reinicia');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(AppError.engine.message)));
    }
    // Sin proxy no hay extractor: la URL del servidor es una página, no un video.
    if (!await MediaFlowService.ensureRunning()) throw AppError.engine;

    final host = _mapServerNameToProxyHost(server.nombre);
    final proxyUrl = MediaFlowService.buildUrl(host, server.url);
    _log.add('[REQUEST] GET host=$host'
        '${host != server.nombre.trim().toLowerCase() ? ' (alias: ${server.nombre})' : ''}');
    // No dejamos la contraseña en el log.
    _log.add('  ${DebugLog.short(proxyUrl.replaceAll(MediaFlowService.apiPassword, '***'))}');

    // El endpoint devuelve un JSON con el destination_url; no es el video.
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.plain,
    ));
    try {
      final response = await dio.get<String>(proxyUrl);
      final body = response.data ?? '';
      final data = jsonDecode(body);
      final destUrl = data is Map ? data['destination_url'] : null;
      if (destUrl is String && destUrl.isNotEmpty) {
        _log.add('[SUCCESS] destination_url: ${DebugLog.short(destUrl)}');
        final map = data as Map;
        _log.add('[INFO] campos del proxy: ${map.keys.join(', ')}');
        final headers = _extractHeaders(map['request_headers']);
        if (headers != null) {
          _log.add('[HEADERS] ${DebugLog.short(headers.entries.map((e) => '${e.key}: ${e.value}').join(' | '), 200)}');
        }
        return (
          url: destUrl,
          headers: headers,
          streamUrl: _absoluteProxyUrl(map['mediaflow_proxy_url']),
          host: host,
        );
      }
      _log.add('[ERROR] ${server.nombre}: sin destination_url (HTTP ${response.statusCode}) '
          '${DebugLog.short(body, 200)}');
    } on DioException catch (e) {
      final body = e.response?.data?.toString() ?? '';
      _log.add('[ERROR] ${server.nombre}: HTTP ${e.response?.statusCode ?? '-'} '
          '${DebugLog.short(body.isNotEmpty ? body : (e.message ?? e.type.name), 200)}');
    } catch (e) {
      _log.add('[ERROR] ${server.nombre}: ${DebugLog.short(e.toString(), 200)}');
    } finally {
      dio.close();
    }
    _log.add('[WARN] Fallback a URL directa');
    return direct;
  }

  /// `mediaflow_proxy_url` puede venir absoluta o como ruta relativa al proxy.
  String? _absoluteProxyUrl(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '${MediaFlowService.proxyUrl}${raw.startsWith('/') ? '' : '/'}$raw';
  }

  /// Toma Referer y User-Agent de `request_headers` (sin distinguir mayúsculas).
  Map<String, String>? _extractHeaders(Object? raw) {
    if (raw is! Map) return null;
    final lower = {for (final e in raw.entries) e.key.toString().toLowerCase(): e.value};
    final headers = <String, String>{
      if (lower['referer'] != null) 'Referer': lower['referer'].toString(),
      if (lower['user-agent'] != null) 'User-Agent': lower['user-agent'].toString(),
    };
    return headers.isEmpty ? null : headers;
  }

    Future<void> _select(int i) async {
    _errorTimer?.cancel();
    _errorShownAt = null;
    _watchdog.connecting();
    setState(() {
      _selected = i;
      _opening = true;
      _playError = null;
    });
    try {
      final video = await _getProxiedUrl(_servers[i]);
      if (!mounted || _selected != i) return;

      final playback = MediaFlowService.playbackUrl(
        host: video.host,
        directUrl: video.url,
        proxyUrl: video.streamUrl,
      );
      final viaProxy = playback.viaProxy;
      final finalUrl = playback.url;
      if (!viaProxy) {
        _log.add('[WARN] el proxy no devolvió mediaflow_proxy_url; se abre directo (puede dar 403)');
      }

      _log.add('[PLAY] media_kit open${viaProxy ? ' (vía proxy)' : ''}: '
          '${DebugLog.short(finalUrl.replaceAll(MediaFlowService.apiPassword, '***'))}');
      if (_resume > Duration.zero) _log.add('[INFO] Reanudando en ${_resume.inSeconds}s');
      _guard = ResumeGuard(_resume);
      _durationLogged = false;
      _media = Media(
        finalUrl,
        httpHeaders: viaProxy ? null : video.headers,
        start: _resume > Duration.zero ? _resume : null,
      );
      _watchdog.begin();
      await _player.open(_media!);
    } catch (e) {
      _log.add('[PLAYER] ${DebugLog.short(e.toString(), 300)}');
      _watchdog.stop();
      if (mounted && _selected == i) setState(() => _playError = e.toString());
    } finally {
      if (mounted && _selected == i) setState(() => _opening = false);
    }
  }

  Widget _videoArea() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PremiumVideo(
            player: _player,
            controller: _controller,
            phase: _watchdog.phase,
            live: false,
            connectingLabel: 'Conectando al servidor...',
          ),
          if (_playError != null && !_opening)
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.textMuted, size: 36),
                  const SizedBox(height: 8),
                  Text(_friendlyPlayerError(_playError!),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _select(_selected),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('REINTENTAR'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return ErrorState(error: _error, onRetry: _load);
    }
    if (_servers.isEmpty) {
      return const EmptyState(
        icon: Icons.videocam_off_rounded,
        title: 'Sin servidores disponibles',
        subtitle: 'Este episodio aún no tiene reproductores.',
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _videoArea(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(widget.animeTitulo,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('${episodeLabel(widget.numero)} • ${episodeName(widget.numero)}',
                style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w600)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text('SERVIDORES',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _servers.length; i++)
                  ChoiceChip(
                    label: Text(
                        _servers[i].nombre.isEmpty ? 'Servidor ${i + 1}' : _servers[i].nombre),
                    selected: i == _selected,
                    onSelected: (_) => _select(i),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(episodeName(widget.numero),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            Text(widget.animeTitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Consola de depuración',
            icon: Icon(Icons.bug_report_outlined,
                color: _showConsole ? AppColors.primary : null),
            onPressed: () => setState(() => _showConsole = !_showConsole),
          ),
          if (_servers.isNotEmpty)
            IconButton(
              tooltip: 'Abrir en navegador',
              icon: const Icon(Icons.open_in_new_rounded),
              onPressed: () => launchUrl(Uri.parse(_servers[_selected].url),
                  mode: LaunchMode.externalApplication),
            ),
        ],
      ),
      body: Stack(
        children: [
          _body(),
          if (_showConsole)
            DebugConsole(log: _log, onClose: () => setState(() => _showConsole = false)),
        ],
      ),
    );
  }
}