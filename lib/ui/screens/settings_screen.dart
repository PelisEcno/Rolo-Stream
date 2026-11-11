import 'package:flutter/material.dart';
import 'package:rolostream_core/rolostream_core.dart';
import '../../services/auth_service.dart';
import '../../services/favorites_service.dart';
import '../../services/profile_service.dart';
import '../../services/source_registry.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/source_picker.dart';
import 'about_screen.dart';
import 'iptv_manager_screen.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _clearFavorites(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('Tus perfiles y tu progreso seguirán en este dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('CERRAR SESIÓN')),
        ],
      ),
    );
    if (ok == true) await AuthService.instance.signOut();
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
                ProfileAvatar(avatar: ProfileService.instance.active?.avatar ?? 0, size: 64),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ProfileService.instance.active?.nombre ?? 'RoloStream',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    if (AuthService.instance.user?.email != null)
                      Text(AuthService.instance.user!.email!,
                          style: const TextStyle(color: AppColors.textMuted)),
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
          _tile(Icons.switch_account_rounded, 'Cambiar de perfil',
              onTap: ProfileService.instance.clearActive),
          const Divider(height: 1),
          _tile(Icons.delete_outline_rounded, 'Vaciar Mi lista',
              onTap: () => _clearFavorites(context)),
          const Divider(height: 1),
          _tile(Icons.live_tv_rounded, 'Listas IPTV',
              subtitle: 'Tus listas M3U o Xtream Codes',
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const IPTVManagerScreen()))),
          const Divider(height: 1),
          StreamBuilder<SourcePlugin>(
            stream: pluginRegistry.changes,
            initialData: pluginRegistry.active,
            builder: (context, snap) => _tile(Icons.extension_outlined, 'Fuente',
                subtitle: snap.data!.name, onTap: () => showSourcePicker(context)),
          ),
          const Divider(height: 1),
          _tile(Icons.info_outline_rounded, 'Acerca de',
              subtitle: 'Versión $appVersion · Colabora en GitHub',
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
          if (!AuthService.instance.isLocal) ...[
            const Divider(height: 1),
            _tile(Icons.logout_rounded, 'Cerrar sesión', onTap: () => _signOut(context)),
          ],
        ],
      ),
    );
  }
}
