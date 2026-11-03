import 'package:flutter/material.dart';
import 'package:rolostream_core/rolostream_core.dart';
import '../../services/source_registry.dart';
import '../theme/app_theme.dart';

/// Hoja inferior para elegir la fuente activa.
Future<void> showSourcePicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Fuente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const Divider(height: 1),
          for (final s in pluginRegistry.all)
            ListTile(
              leading: Icon(Icons.extension_rounded,
                  color: s.id == pluginRegistry.active.id ? AppColors.primary : AppColors.textMuted),
              title: Text(s.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: s.id == pluginRegistry.active.id ? AppColors.primary : null)),
              trailing: s.id == pluginRegistry.active.id
                  ? const Icon(Icons.check_rounded, color: AppColors.primary)
                  : null,
              onTap: () {
                pluginRegistry.select(s.id);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Botón compacto con el nombre de la fuente activa; abre el selector.
class SourceButton extends StatelessWidget {
  const SourceButton({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SourcePlugin>(
      stream: pluginRegistry.changes,
      initialData: pluginRegistry.active,
      builder: (context, snap) => TextButton.icon(
        onPressed: () => showSourcePicker(context),
        icon: const Icon(Icons.arrow_drop_down_rounded, color: Colors.white70),
        label: Text(snap.data!.name.toUpperCase(),
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
        iconAlignment: IconAlignment.end,
      ),
    );
  }
}
