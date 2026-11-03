import 'dart:async';

import 'package:flutter/material.dart';
import '../../iptv/epg.dart';
import '../../iptv/iptv_models.dart';
import '../../iptv/iptv_service.dart';
import '../../iptv/m3u_parser.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import '../widgets/epg_timeline.dart';
import 'iptv_player_screen.dart';

/// Canales de una lista: cuadrícula por `group-title`, búsqueda y guía de programación.
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
              error: snap.error,
              // Estos ya dicen qué pasó con la lista (usuario y contraseña, URL…).
              message: snap.error is IPTVException ? snap.error.toString() : null,
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
  late String _group = _groups.keys.first;
  bool _guide = false;
  final _search = TextEditingController();
  final _grid = ScrollController();
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
    _grid.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = text.trim().toLowerCase());
    });
  }

  void _selectGroup(String group) {
    setState(() => _group = group);
    if (_grid.hasClients) _grid.jumpTo(0);
  }

  void _play(Channel c) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IPTVPlayerScreen(channel: c)),
      );

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

  Widget _guideView() {
    final channels = _guideChannels();
    if (channels.isNotEmpty) return EpgTimeline(channels: channels, onPlay: _play);
    final hasData = EPGService.instance.hasData;
    return EmptyState(
      icon: Icons.calendar_view_day_rounded,
      title: hasData ? 'Sin resultados' : 'Aún no hay guía de programación',
      subtitle: hasData
          ? 'Prueba con otro nombre.'
          : 'Cuando la lista incluya datos de programación, aparecerán aquí.',
    );
  }

  Widget _gridView(List<Channel> items, {required bool searching}) {
    if (items.isEmpty) {
      return const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Sin resultados',
          subtitle: 'Prueba con otro nombre.');
    }
    // Perezosa: un grupo de miles de canales solo cuesta lo que se ve en pantalla.
    return GridView.builder(
      controller: _grid,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 128,
        mainAxisExtent: 172,
        crossAxisSpacing: 10,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (_, i) =>
          _ChannelTile(channel: items[i], showGroup: searching, onTap: () => _play(items[i])),
    );
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
    final results = !_guide && searching ? _searchResults() : const <Channel>[];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
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
                icon: Icon(_guide ? Icons.grid_view_rounded : Icons.calendar_view_day_rounded,
                    color: _guide ? AppColors.primary : AppColors.textMuted),
                onPressed: () => setState(() => _guide = !_guide),
              ),
            ],
          ),
        ),
        if (!_guide && !searching)
          _GroupTabs(groups: _groups, selected: _group, onSelected: _selectGroup),
        if (!_guide && searching && results.length >= _maxSearchResults)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Mostrando los primeros $_maxSearchResults resultados. Afina la búsqueda.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ),
        Expanded(
          child: _guide
              ? _guideView()
              : _gridView(searching ? results : _groups[_group]!, searching: searching),
        ),
      ],
    );
  }
}

/// Pestañas de grupos, con el subrayado del grupo activo.
class _GroupTabs extends StatelessWidget {
  final Map<String, List<Channel>> groups;
  final String selected;
  final void Function(String) onSelected;
  const _GroupTabs({required this.groups, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final names = groups.keys.toList(growable: false);
    return Container(
      height: 42,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: names.length,
        itemBuilder: (_, i) {
          final name = names[i];
          final active = name == selected;
          return InkWell(
            onTap: () => onSelected(name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                      width: 2, color: active ? AppColors.primary : Colors.transparent),
                ),
              ),
              child: Row(
                children: [
                  Text(name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : AppColors.textMuted)),
                  const SizedBox(width: 5),
                  Text('${groups[name]!.length}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Logo del canal con su nombre y, si los hay, grupo y "Ahora" / "Después".
class _ChannelTile extends StatelessWidget {
  final Channel channel;
  final bool showGroup;
  final VoidCallback onTap;
  const _ChannelTile({required this.channel, required this.showGroup, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final nn = EPGService.instance.nowNextFor(channel);
    final ahora = nn?.ahora;
    final despues = nn?.despues;
    const muted = TextStyle(color: AppColors.textMuted, fontSize: 11);
    Widget line(String text, [TextStyle style = muted]) =>
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);

    return PressScale(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: RoundedPoster(
              child: Container(
                width: double.infinity,
                color: AppColors.surface,
                padding: const EdgeInsets.all(10),
                child: channel.logo == null
                    ? const Icon(Icons.live_tv_rounded, size: 30, color: AppColors.textMuted)
                    : PosterImage(url: channel.logo!, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(channel.nombre,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2)),
          if (showGroup) line(channel.grupo),
          if (ahora != null)
            line('Ahora: ${ahora.titulo}',
                const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
          if (despues != null) line('Después: ${despues.titulo}'),
        ],
      ),
    );
  }
}
