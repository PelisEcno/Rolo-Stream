import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/favorites_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearFavorites(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        title: const Text('Vaciar Mi lista'),
        content: const Text('Se eliminarán todas las series guardadas. ¿Continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('VACIAR')),
        ],
      ),
    );
    if (ok == true) await FavoritesService.instance.clear();
  }

  Widget _tile(IconData icon, String title, {String? subtitle, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.textMuted),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, style: const TextStyle(color: AppColors.textMuted)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuenta')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: AppColors.primary,
                  child: Icon(Icons.person_rounded, size: 36, color: Colors.black),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('RoloStream',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    ListenableBuilder(
                      listenable: FavoritesService.instance,
                      builder: (_, __) => Text(
                        '${FavoritesService.instance.items.length} series en Mi lista',
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          _tile(Icons.delete_outline_rounded, 'Vaciar Mi lista',
              onTap: () => _clearFavorites(context)),
          const Divider(height: 1),
          _tile(Icons.extension_outlined, 'Fuente',
              subtitle: 'Latanime',
              onTap: () => launchUrl(Uri.parse('https://latanime.org'),
                  mode: LaunchMode.externalApplication)),
          const Divider(height: 1),
          _tile(Icons.info_outline_rounded, 'Acerca de',
              subtitle: 'Versión 0.1.0',
              onTap: () => showAboutDialog(
                    context: context,
                    applicationName: 'RoloStream',
                    applicationVersion: '0.1.0',
                    applicationLegalese: 'Reproductor de anime multiplataforma.',
                  )),
        ],
      ),
    );
  }
}
