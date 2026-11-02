import 'package:flutter/material.dart';
import '../../iptv/iptv_models.dart';
import '../../iptv/iptv_service.dart';
import '../theme/app_theme.dart';
import '../widgets/anime_card.dart';
import 'iptv_channel_list_screen.dart';

/// Listas IPTV guardadas: añadir, abrir y eliminar.
class IPTVManagerScreen extends StatelessWidget {
  const IPTVManagerScreen({super.key});

  Future<void> _addPlaylist(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddPlaylistDialog(),
    );
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Lista añadida')));
    }
  }

  Future<void> _confirmDelete(BuildContext context, IPTVPlaylist p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text('Eliminar lista'),
        content: Text('Se quitará "${p.nombre}" de la app. La lista en el servidor no se toca.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ELIMINAR')),
        ],
      ),
    );
    if (ok == true) await IPTVService.instance.remove(p.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Listas IPTV')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPlaylist(context),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('AÑADIR LISTA', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: ListenableBuilder(
        listenable: IPTVService.instance,
        builder: (context, _) {
          final lists = IPTVService.instance.playlists;
          if (lists.isEmpty) {
            return const EmptyState(
              icon: Icons.live_tv_rounded,
              title: 'Aún no tienes listas',
              subtitle: 'Añade la URL de una lista M3U o de Xtream Codes para ver sus canales.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: lists.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final p = lists[i];
              return Card(
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  leading: const Icon(Icons.playlist_play_rounded, color: AppColors.primary, size: 32),
                  title: Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                  // Solo el servidor: la URL completa lleva usuario y contraseña.
                  subtitle: Text('${p.tipoLabel} · ${p.host}',
                      style: const TextStyle(color: AppColors.textMuted)),
                  trailing: IconButton(
                    tooltip: 'Eliminar',
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.textMuted),
                    onPressed: () => _confirmDelete(context, p),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => IPTVChannelListScreen(playlist: p)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _AddPlaylistDialog extends StatefulWidget {
  const _AddPlaylistDialog();

  @override
  State<_AddPlaylistDialog> createState() => _AddPlaylistDialogState();
}

class _AddPlaylistDialogState extends State<_AddPlaylistDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    await IPTVService.instance.add(nombre: _name.text, url: _url.text);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surfaceHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      title: const Text('Añadir lista'),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nombre (opcional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'URL de la lista',
                hintText: 'http://servidor/lista.m3u',
                helperText: 'M3U o Xtream Codes (get.php?username=…&password=…)',
                helperMaxLines: 2,
              ),
              validator: (v) => IPTVService.validateUrl(v ?? ''),
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
        TextButton(onPressed: _submit, child: const Text('AÑADIR')),
      ],
    );
  }
}
