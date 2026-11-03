import 'dart:async';

import 'package:flutter/material.dart';
import '../../iptv/epg.dart';
import '../../iptv/iptv_models.dart';
import '../../iptv/iptv_service.dart';
import '../../iptv/m3u_parser.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'iptv_player_screen.dart';

/// Canales de una lista, agrupados por `group-title`, con búsqueda.
class IPTVChannelListScreen extends StatefulWidget {
  final IPTVPlaylist playlist;
  const IPTVChannelListScreen({super.key, required this.playlist});

  @override
  State<IPTVChannelListScreen> createState() => _IPTVChannelListScreenState();
}

class _IPTVChannelListScreenState extends State<IPTVChannelListScreen> {
  late Future<List<Channel>> _future;

  @override
  void initState() {
    super.initState();
    _future = IPTVService.instance.channelsFor(widget.playlist);
  }

  void _reload({bool refresh = false}) => setState(
      () => _future = IPTVService.instance.channelsFor(widget.playlist, refresh: refresh));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.playlist.nombre, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Descargar de nuevo',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _reload(refresh: true),
          ),
        ],
      ),
      body: FutureBuilder<List<Channel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Descargando la lista…',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    SizedBox(height: 4),
                    Text('Las listas grandes pueden tardar unos segundos.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textMuted)),
                  ],
                ),
              ),
            );
          }
          if (snap.hasError) {
            return ErrorState(
              title: 'No se pudo cargar la lista',
              detail: snap.error.toString(),
              onRetry: _reload,
            );
          }
          return _ChannelBrowser(channels: snap.data!);
        },
      ),
    );
  }
}

/// Máximo de resultados que se pintan al buscar (una lista puede tener 100 000+ entradas).
const _maxSearchResults = 500;

class _ChannelBrowser extends StatefulWidget {
  final List<Channel> channels;
  const _ChannelBrowser({required this.channels});

  @override
  State<_ChannelBrowser> createState() => _ChannelBrowserState();
}

class _ChannelBrowserState extends State<_ChannelBrowser> {
  late final Map<String, List<Channel>> _groups = groupChannels(widget.channels);
  final _expanded = <String>{};
  bool _guide = false;
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    // "Ahora" y "Después" cambian con la hora aunque no lleguen datos nuevos.
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (EPGService.instance.hasData) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = text.trim().toLowerCase());
    });
  }

  void _toggle(String group) =>
      setState(() => _expanded.contains(group) ? _expanded.remove(group) : _expanded.add(group));

  void _play(Channel c) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IPTVPlayerScreen(channel: c)),
      );

  /// Cabeceras de grupo y, debajo de cada grupo abierto, sus canales. La lista es perezosa
  /// (`ListView.builder`), así que un grupo de miles de canales no cuesta nada hasta que se mira.
  List<Object> _grouped() => [
        for (final e in _groups.entries) ...[
          e.key,
          if (_expanded.contains(e.key)) ...e.value,
        ],
      ];

  List<Channel> _searchResults() {
    final out = <Channel>[];
    for (final c in widget.channels) {
      if (c.nombre.toLowerCase().contains(_query)) {
        out.add(c);
        if (out.length >= _maxSearchResults) break;
      }
    }
    return out;
  }

  /// Canales con datos de guía (que además coincidan con la búsqueda), con un tope.
  List<Channel> _guideChannels() {
    final out = <Channel>[];
    for (final c in widget.channels) {
      if (EPGService.instance.scheduleFor(c) == null) continue;
      if (_query.isNotEmpty && !c.nombre.toLowerCase().contains(_query)) continue;
      out.add(c);
      if (out.length >= _maxSearchResults) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    // La guía se rellena desde fuera (XMLTV): al cambiar, se repinta la lista.
    return ListenableBuilder(
      listenable: EPGService.instance,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final searching = _query.isNotEmpty;
    final items = _guide ? const <Object>[] : (searching ? _searchResults() : _grouped());

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: _onQuery,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar entre ${widget.channels.length} canales',
                    prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                            onPressed: () {
                              _search.clear();
                              _onQuery('');
                            },
                          ),
                  ),
                ),
              ),
              IconButton(
                tooltip: _guide ? 'Ver canales' : 'Guía de programación',
                icon: Icon(_guide ? Icons.view_list_rounded : Icons.calendar_view_day_rounded,
                    color: _guide ? AppColors.primary : AppColors.textMuted),
                onPressed: () => setState(() => _guide = !_guide),
              ),
            ],
          ),
        ),
        if (!_guide && searching && items.length >= _maxSearchResults)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Mostrando los primeros $_maxSearchResults resultados. Afina la búsqueda.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
        Expanded(
          child: _guide
              ? _GuideView(channels: _guideChannels(), onPlay: _play)
              : items.isEmpty
              ? const EmptyState(
                  icon: Icons.search_off_rounded,
                  title: 'Sin resultados',
                  subtitle: 'Prueba con otro nombre.')
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    if (item is String) {
                      return _GroupHeader(
                        name: item,
                        count: _groups[item]!.length,
                        expanded: _expanded.contains(item),
                        onTap: () => _toggle(item),
                      );
                    }
                    final c = item as Channel;
                    return _ChannelTile(channel: c, showGroup: searching, onTap: () => _play(c));
                  },
                ),
        ),
      ],
    );
  }
}

/// Cabecera plegable de un grupo (hace el papel de un `ExpansionTile`).
class _GroupHeader extends StatelessWidget {
  final String name;
  final int count;
  final bool expanded;
  final VoidCallback onTap;
  const _GroupHeader(
      {required this.name, required this.count, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: expanded ? AppColors.primary : null)),
              ),
              const SizedBox(width: 8),
              Text('$count', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              const SizedBox(width: 4),
              Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool showGroup;
  final VoidCallback onTap;
  const _ChannelTile({required this.channel, required this.showGroup, required this.onTap});

  /// Grupo (en búsquedas) y, si el canal tiene guía, "Ahora" y "Después".
  Widget? _subtitle() {
    final nn = EPGService.instance.nowNextFor(channel);
    if (!showGroup && nn == null) return null;
    const muted = TextStyle(color: AppColors.textMuted, fontSize: 12);
    Widget line(String text, [TextStyle style = muted]) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    final ahora = nn?.ahora;
    final despues = nn?.despues;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showGroup) line(channel.grupo),
        if (ahora != null)
          line('Ahora: ${ahora.titulo}',
              const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)),
        if (despues != null) line('Después: ${despues.titulo}'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      contentPadding: const EdgeInsets.fromLTRB(24, 2, 12, 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.small),
        child: Container(
          width: 44,
          height: 44,
          color: AppColors.surfaceHigh,
          child: channel.logo == null
              ? const Icon(Icons.tv_rounded, color: AppColors.textMuted)
              : PosterImage(url: channel.logo!, fit: BoxFit.contain),
        ),
      ),
      title: Text(channel.nombre, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: _subtitle(),
      trailing: const Icon(Icons.play_arrow_rounded, color: AppColors.primary),
    );
  }
}

/// Guía de programación: una fila por canal con lo que emite ahora (con su progreso) y lo siguiente.
class _GuideView extends StatelessWidget {
  final List<Channel> channels;
  final void Function(Channel) onPlay;
  const _GuideView({required this.channels, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      final hasData = EPGService.instance.hasData;
      return EmptyState(
        icon: Icons.calendar_view_day_rounded,
        title: hasData ? 'Sin resultados' : 'Aún no hay guía de programación',
        subtitle: hasData
            ? 'Prueba con otro nombre.'
            : 'Cuando la lista incluya datos de programación, aparecerán aquí.',
      );
    }
    final now = DateTime.now();
    return ListView.separated(
      itemCount: channels.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.divider),
      itemBuilder: (context, i) {
        final c = channels[i];
        final nn = EPGService.instance.nowNextFor(c, now: now);
        final ahora = nn?.ahora;
        final despues = nn?.despues;
        return InkWell(
          onTap: () => onPlay(c),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                if (ahora != null) ...[
                  Text('Ahora · ${ahora.rango}',
                      style: const TextStyle(
                          color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                  Text(ahora.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(
                    value: ahora.progressAt(now),
                    minHeight: 3,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surfaceHigh,
                  ),
                ],
                if (despues != null) ...[
                  const SizedBox(height: 6),
                  Text('Después · ${despues.rango}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  Text(despues.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
