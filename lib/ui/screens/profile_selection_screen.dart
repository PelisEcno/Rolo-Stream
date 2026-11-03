import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/profile_avatar.dart';

/// "¿Quién está viendo?": elegir, crear (hasta 4) y administrar perfiles.
class ProfileSelectionScreen extends StatefulWidget {
  const ProfileSelectionScreen({super.key});

  @override
  State<ProfileSelectionScreen> createState() => _ProfileSelectionScreenState();
}

class _ProfileSelectionScreenState extends State<ProfileSelectionScreen> {
  final _service = ProfileService.instance;
  bool _managing = false;

  void _edit([Profile? profile]) {
    showDialog<void>(context: context, builder: (_) => _ProfileEditor(profile: profile));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _service,
          builder: (context, _) {
            final profiles = _service.profiles;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_managing ? 'Administrar perfiles' : '¿Quién está viendo?',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 32),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 20,
                      runSpacing: 24,
                      children: [
                        for (final p in profiles)
                          _ProfileTile(
                            nombre: p.nombre,
                            avatar: ProfileAvatar(avatar: p.avatar),
                            editing: _managing,
                            onTap: () => _managing ? _edit(p) : _service.select(p),
                          ),
                        if (_service.canAdd && !_managing)
                          _ProfileTile(
                            nombre: 'Añadir perfil',
                            avatar: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHigh,
                                borderRadius: BorderRadius.circular(96 * 0.18),
                              ),
                              child: const Icon(Icons.add_rounded,
                                  size: 44, color: AppColors.textMuted),
                            ),
                            onTap: _edit,
                          ),
                      ],
                    ),
                    if (profiles.isNotEmpty) ...[
                      const SizedBox(height: 36),
                      _managing
                          ? FilledButton(
                              onPressed: () => setState(() => _managing = false),
                              child: const Text('LISTO'),
                            )
                          : OutlinedButton.icon(
                              onPressed: () => setState(() => _managing = true),
                              icon: const Icon(Icons.edit_rounded, size: 18),
                              label: const Text('Administrar perfiles'),
                            ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final String nombre;
  final Widget avatar;
  final VoidCallback onTap;
  final bool editing;
  const _ProfileTile(
      {required this.nombre, required this.avatar, required this.onTap, this.editing = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 112,
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                avatar,
                if (editing)
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(96 * 0.18),
                    ),
                    child: const Icon(Icons.edit_rounded, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(nombre,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ProfileEditor extends StatefulWidget {
  final Profile? profile;
  const _ProfileEditor({this.profile});

  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.profile?.nombre ?? '');
  late int _avatar = widget.profile?.avatar ?? 0;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final service = ProfileService.instance;
    final p = widget.profile;
    if (p == null) {
      await service.add(nombre: _name.text, avatar: _avatar);
    } else {
      await service.update(p.id, nombre: _name.text, avatar: _avatar);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final p = widget.profile!;
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar perfil'),
        content: Text('Se eliminará "${p.nombre}" y todo su progreso. Esto no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('CANCELAR')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ELIMINAR')),
        ],
      ),
    );
    if (ok != true) return;
    await ProfileService.instance.remove(p.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.profile == null ? 'Nuevo perfil' : 'Editar perfil'),
      content: SizedBox(
        width: 320,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre', counterText: ''),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe un nombre' : null,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < kProfileAvatars.length; i++)
                      GestureDetector(
                        key: ValueKey('avatar-$i'),
                        onTap: () => setState(() => _avatar = i),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                width: 2,
                                color: i == _avatar ? AppColors.primary : Colors.transparent),
                          ),
                          child: ProfileAvatar(avatar: i, size: 52),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.profile != null)
          TextButton(onPressed: _delete, child: const Text('ELIMINAR')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
        TextButton(onPressed: _save, child: const Text('GUARDAR')),
      ],
    );
  }
}
