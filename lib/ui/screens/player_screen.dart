import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:rolostream_core/rolostream_core.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/app_error.dart';
import '../../services/exo_engine.dart';
import '../../services/mdk_engine.dart';
import '../../services/mediaflow_service.dart';
import '../../services/source_registry.dart';
import '../../services/watch_progress_service.dart';
import '../theme/app_theme.dart';
import '../utils/episode_label.dart';
import '../widgets/anime_card.dart';
import '../widgets/debug_console.dart';
import '../widgets/engine_video.dart';
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

/// Servidores con los que FFmpeg, dentro de `media_kit`, se queda clavado al saltar a un segmento sin
/// cargar: en iOS usan el motor de `fvp`.
const _mdkHosts = {'zilla', 'byse'};

/// En Android todo se reproduce con ExoPlayer (Media3): `media_kit` falla en demasiados dispositivos.
bool get _androidUsesExo => defaultTargetPlatform == TargetPlatform.android;

class _PlayerScreenState extends State<PlayerScreen> {
  late final SourcePlugin _source =
      pluginRegistry.byId(widget.sourceId ?? '') ?? pluginRegistry.active;
  // `warn` deja pasar los avisos de FFmpeg/mpv (hls, tcp, http…) a la consola de depuración.
  late final Player _player = createPremiumPlayer(logLevel: MPVLogLevel.warn);
  late final VideoController _controller = createPremiumController(_player);

  /// Motor alternativo a `media_kit`, creado solo si hace falta.
  VideoEngine? _alt;
  String? _altUrl;
  Map<String, String>? _altHeaders;
  final _altActive = ValueNotifier<bool>(false);

  /// Posición del motor en uso.
  final _positions = StreamController<Duration>.broadcast();

  late final PlaybackWatchdog _watchdog = PlaybackWatchdog.withSource(
    position: _positions.stream,
    shouldWatch: () =>
        _altActive.value ? _engine.playing.value && !_engine.completed : _player.state.playing && !_player.state.completed,
    reopen: (at) async {
      if (_guard.shouldFallBackToStart()) {
        await _openFromStart();
        return;
      }
      if (_altActive.value) {
        // Si se quedó clavado tras un salto, la posición ya está en el destino.
        final stuck = _engine.position > at ? _engine.position : at;
        final target = stuck > _resume ? stuck : _resume;
        _log.add('[WARN] El video no avanza: se reabre en ${target.inSeconds}s');
        _watchdog.resetPosition();
        await _engine.open(_altUrl!, start: target, headers: _altHeaders);
        return;
      }
      // Si aún no se llegó al punto guardado, `at` es anterior a él.
      final target = at > _resume ? at : _resume;
      _log.add('[WARN] El video no avanza: se reabre en ${target.inSeconds}s');
      await reopenAt(_player, _media!, target);
    },
    onGiveUp: () {
      if (!mounted) return;
      _errorShownAt = _currentPosition; // el aviso se quita solo si el video vuelve a avanzar
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

  /// Punto guardado al que este servidor no pudo llegar: no se pisa hasta superarlo, para poder
  /// retomarlo con otro servidor.
  Duration? _unreachedResume;
  bool _durationLogged = false;

  VideoEngine get _engine {
    final existing = _alt;
    if (existing != null) return existing;
    final VideoEngine engine =
        _androidUsesExo ? ExoEngine(onLog: _log.add) : MdkEngine(onLog: _log.add);
    engine.positionStream.listen((p) {
      if (_altActive.value) _positions.add(p);
    });
    engine.errors.listen(_onEngineError);
    return _alt = engine;
  }

  Duration get _currentPosition => _altActive.value ? _engine.position : _player.state.position;
  Duration get _currentDuration => _altActive.value ? _engine.duration : _player.state.duration;
  bool get _isPlaying => _altActive.value ? _engine.playing.value : _player.state.playing;

  /// Número del episodio siguiente, si existe.
  final _nextNumero = ValueNotifier<int?>(null);

  Future<void> _findNextEpisode() async {
    try {
      final detail = await _source.getAnime(widget.slug);
      final later = [for (final e in detail.episodios) if (e.numero > widget.numero) e.numero]..sort();
      if (mounted && later.isNotEmpty) _nextNumero.value = later.first;
    } catch (_) {
      // Sin la lista de episodios simplemente no hay botón de "Siguiente".
    }
  }

  void _openEpisode(int numero) {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(
        slug: widget.slug,
        numero: numero,
        animeTitulo: widget.animeTitulo,
        imagen: widget.imagen,
        sourceId: _source.id,
      ),
    ));
  }

  int _av1Errors = 0;
  int _av1ErrorsLogged = 0;

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
      if (l.prefix == 'ffmpeg' && DebugLog.isAv1ParserNoise(l.text)) {
        if (_av1Errors++ == 0) {
          _log.add('[WARN] Parser AV1: ${DebugLog.short(l.text, 120)} (se agrupan los siguientes)');
        }
        return;
      }
      final tag = l.level == 'error' || l.level == 'fatal' ? '[PLAYER]' : '[WARN]';
      _log.add('$tag mpv ${l.prefix}: ${DebugLog.short(l.text, 220)}');
    });
    _player.stream.position.listen((p) {
      if (!_altActive.value) _positions.add(p);
    });
    // Si el video avanza después de un error, el error era transitorio: quitamos el aviso.
    _positions.stream.listen((pos) {
      final at = _errorShownAt;
      if (_playError != null &&
          at != null &&
          _isPlaying &&
          pos - at > const Duration(seconds: 1)) {
        _errorShownAt = null;
        _watchdog.begin();
        if (mounted) setState(() => _playError = null);
      }
    });
    _positions.stream.listen(_verifyResume);
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (_) => _saveProgress());
    _load();
    _findNextEpisode();
  }

  Future<void> _openFromStart() async {
    final saved = _resume;
    _log.add('[WARN] No arrancó en ${saved.inSeconds}s: se abre desde el inicio');
    _unreachedResume = saved;
    _resume = Duration.zero;
    _guard = ResumeGuard(Duration.zero);
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            content: Text('Este servidor no pudo retomar donde ibas: empieza desde el inicio. '
                'Con otro servidor puedes retomarlo.')));
    }
    if (_altActive.value) {
      _watchdog.resetPosition();
      await _engine.open(_altUrl!, headers: _altHeaders);
      return;
    }
    final old = _media!;
    _media = Media(old.uri, httpHeaders: old.httpHeaders);
    await _player.open(_media!);
  }

  void _onEngineError(String message) {
    _log.add('[PLAYER] ${DebugLog.short(message, 300)}');
    if (!mounted || !_altActive.value) return;
    _watchdog.stop();
    setState(() => _playError = message);
  }

  /// Con el video ya avanzando, salta al punto guardado si `Media.start` no se cumplió.
  void _verifyResume(Duration position) {
    if (_watchdog.phase.value != PlaybackPhase.playing) return;
    final duration = _currentDuration;
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
      _altActive.value ? _engine.seek(jump) : _player.seek(jump);
    } else if (_guard.gaveUp) {
      _guard.gaveUp = false;
      _log.add('[WARN] Este servidor no permitió saltar a ${_guard.target.inSeconds}s');
    }
  }

  void _saveProgress() {
    if (_av1Errors != _av1ErrorsLogged) {
      _av1ErrorsLogged = _av1Errors;
      _log.add('[WARN] Parser AV1: $_av1Errors errores; video en '
          '${_currentPosition.inSeconds}s de ${_currentDuration.inSeconds}s');
    }
    // Solo con el video avanzando: al abrir o reabrir, la posición pasa un momento por 0.
    if (_watchdog.phase.value != PlaybackPhase.playing) return;
    if (!_guard.done) return;
    final position = _currentPosition;
    if (position == _resume) return;
    _resume = position;
    final unreached = _unreachedResume;
    if (unreached != null) {
      if (position <= unreached) return;
      _unreachedResume = null;
    }
    WatchProgressService.instance.save(
      sourceId: _source.id,
      slug: widget.slug,
      numero: widget.numero,
      titulo: widget.animeTitulo,
      imagen: widget.imagen,
      position: position,
      duration: _currentDuration,
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
    _alt?.dispose();
    _altActive.dispose();
    _nextNumero.dispose();
    _positions.close();
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

      final useAlt = _androidUsesExo || (viaProxy && _mdkHosts.contains(video.host));
      _log.add('[PLAY] ${useAlt ? _engine.name : 'media_kit'} open${viaProxy ? ' (vía proxy)' : ''}: '
          '${DebugLog.short(finalUrl.replaceAll(MediaFlowService.apiPassword, '***'))}');
      final unreached = _unreachedResume;
      if (unreached != null && unreached > _resume) _resume = unreached;
      _unreachedResume = null;
      if (_resume > Duration.zero) _log.add('[INFO] Reanudando en ${_resume.inSeconds}s');
      _durationLogged = false;
      if (useAlt) {
        try {
          await _openWithAlt(finalUrl, viaProxy ? null : video.headers);
          return;
        } catch (e) {
          // Si el motor no está disponible, `media_kit` al menos reproduce desde donde pueda.
          _log.add('[WARN] ${_engine.name} no disponible (${DebugLog.short(e.toString(), 200)}): '
              'se usa media_kit');
        }
      }
      _alt?.stop();
      _altActive.value = false;
      _guard = ResumeGuard(_resume);
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

  Future<void> _openWithAlt(String url, Map<String, String>? headers) async {
    final engine = _engine;
    await _player.stop();
    _altUrl = url;
    _altHeaders = headers;
    _altActive.value = true;
    // Un salto cae en el fotograma clave anterior, que puede estar varios segundos antes.
    const margin = Duration(seconds: 30);
    _guard = ResumeGuard(_resume > margin ? _resume - margin : Duration.zero);
    _watchdog.begin();
    await engine.open(url, start: _resume, headers: headers);
  }

  Widget _videoArea() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: _altActive,
            builder: (context, useMdk, _) => useMdk
                ? ValueListenableBuilder<int?>(
                    valueListenable: _nextNumero,
                    builder: (context, next, _) => EngineVideoView(
                      model: _engine,
                      surface: _engine.surface(),
                      phase: _watchdog.phase,
                      connectingLabel: 'Conectando al servidor...',
                      title: '${widget.animeTitulo} · ${episodeLabel(widget.numero)}',
                      onNext: next == null ? null : () => _openEpisode(next),
                    ),
                  )
                : PremiumVideo(
                    player: _player,
                    controller: _controller,
                    phase: _watchdog.phase,
                    live: false,
                    connectingLabel: 'Conectando al servidor...',
                  ),
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