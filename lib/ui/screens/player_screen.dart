import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:latanime_plugin/latanime_plugin.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/mediaflow_service.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import '../widgets/debug_console.dart';

class PlayerScreen extends StatefulWidget {
  final String slug;
  final int numero;
  final String animeTitulo;

  const PlayerScreen(
      {super.key, required this.slug, required this.numero, required this.animeTitulo});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _plugin = LatanimePlugin();
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  List<VideoServer> _servers = [];
  int _selected = 0;
  bool _loading = true;
  bool _opening = false;
  String? _error;
  String? _playError;

  final _log = DebugLog();
  bool _showConsole = false;

  @override
  void initState() {
    super.initState();
    _player.stream.error.listen((e) {
      if (e.isEmpty) return;
      _log.add('[PLAYER] ${DebugLog.short(e, 300)}');
      if (mounted) setState(() => _playError = e);
    });
    _load();
  }

  @override
  void dispose() {
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
      final servers = await _plugin.getServers(widget.slug, widget.numero);
      if (!mounted) return;
      setState(() => _servers = servers);
      if (servers.isNotEmpty) await _select(0);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _proxyIsRunning() async {
    try {
      final sock = await Socket.connect('127.0.0.1', MediaFlowService.port,
          timeout: const Duration(milliseconds: 600));
      sock.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Obtiene la URL real del video y los headers que el servidor exige
  /// (Referer, User-Agent) a través del proxy.
  /// Si el proxy no responde o falla, devuelve la URL directa sin headers.
  Future<({String url, Map<String, String>? headers})> _getProxiedUrl(
      VideoServer server) async {
    final direct = (url: server.url, headers: null as Map<String, String>?);
    if (!await _proxyIsRunning()) {
      _log.add('[WARN] Proxy no responde en :${MediaFlowService.port}, uso URL directa');
      return direct;
    }

    final proxyUrl = MediaFlowService.buildUrl(server.nombre, server.url);
    _log.add('[REQUEST] GET host=${server.nombre}');
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
        final headers = _extractHeaders((data as Map)['request_headers']);
        if (headers != null) {
          _log.add('[HEADERS] ${DebugLog.short(headers.entries.map((e) => '${e.key}: ${e.value}').join(' | '), 200)}');
        }
        return (url: destUrl, headers: headers);
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
    setState(() {
      _selected = i;
      _opening = true;
      _playError = null;
    });
    try {
      final video = await _getProxiedUrl(_servers[i]);
      if (!mounted || _selected != i) return;

      _log.add('[PLAY] media_kit open: ${DebugLog.short(video.url)}');
      await _player.open(Media(video.url, httpHeaders: video.headers));
    } catch (e) {
      _log.add('[PLAYER] ${DebugLog.short(e.toString(), 300)}');
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
          Video(controller: _controller, controls: MaterialVideoControls),
          if (_opening) const Center(child: CircularProgressIndicator()),
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
                  const Text('No se pudo cargar el video. Intenta con otro servidor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w600)),
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
      return ErrorState(
          title: 'No se pudieron cargar los servidores', detail: _error, onRetry: _load);
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
            child: Text('E${widget.numero} • Episodio ${widget.numero}',
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
            Text('Episodio ${widget.numero}',
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