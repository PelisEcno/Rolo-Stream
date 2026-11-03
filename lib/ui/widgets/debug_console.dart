import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Registro de eventos para la consola de depuración.
class DebugLog extends ChangeNotifier {
  static const _maxLines = 300;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void add(String line) {
    final t = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _lines.add('${two(t.hour)}:${two(t.minute)}:${two(t.second)} $line');
    if (_lines.length > _maxLines) _lines.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  static final _av1ParserNoise = RegExp(
      r'obu_|temporal unit|seq_profile|extension_header_reserved|Failed to read unit|Invalid OBU');

  /// Errores del parser de AV1 de FFmpeg: salen a decenas en una ráfaga y, como el registro guarda
  /// [_maxLines] líneas, borrarían las del arranque.
  static bool isAv1ParserNoise(String text) => _av1ParserNoise.hasMatch(text);

  /// Recorta textos largos (URLs, cuerpos de respuesta) para el log.
  static String short(String s, [int max = 140]) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

/// Panel flotante y arrastrable. Colócalo dentro de un Stack.
class DebugConsole extends StatefulWidget {
  final DebugLog log;
  final VoidCallback onClose;
  const DebugConsole({super.key, required this.log, required this.onClose});

  @override
  State<DebugConsole> createState() => _DebugConsoleState();
}

class _DebugConsoleState extends State<DebugConsole> {
  static const _height = 220.0;
  final _scroll = ScrollController();
  Offset _offset = const Offset(8, 8);

  @override
  void initState() {
    super.initState();
    widget.log.addListener(_toBottom);
  }

  @override
  void dispose() {
    widget.log.removeListener(_toBottom);
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Color _color(String line) {
    if (line.contains('[ERROR]') || line.contains('[PLAYER]')) return const Color(0xFFFF6B6B);
    if (line.contains('[SUCCESS]')) return const Color(0xFF5CD68A);
    if (line.contains('[WARN]')) return const Color(0xFFFFC857);
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width - 16;
    return Positioned(
      left: _offset.dx,
      top: _offset.dy,
      width: width,
      height: _height,
      child: Material(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            // Cabecera: se arrastra desde aquí.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanUpdate: (d) => setState(() {
                final next = _offset + d.delta;
                _offset = Offset(
                  next.dx.clamp(0, size.width - width),
                  next.dy.clamp(0, size.height - _height),
                );
              }),
              child: Container(
                height: 30,
                color: Colors.white10,
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report_rounded, size: 14, color: Colors.white70),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text('DEBUG',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                    ),
                    _HeaderButton(
                      icon: Icons.copy_rounded,
                      tooltip: 'Copiar',
                      onTap: () => Clipboard.setData(
                          ClipboardData(text: widget.log.lines.join('\n'))),
                    ),
                    _HeaderButton(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: 'Limpiar',
                      onTap: widget.log.clear,
                    ),
                    _HeaderButton(
                      icon: Icons.close_rounded,
                      tooltip: 'Cerrar',
                      onTap: widget.onClose,
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.log,
                builder: (context, _) {
                  final lines = widget.log.lines;
                  if (lines.isEmpty) {
                    return const Center(
                      child: Text('Sin eventos. Elige un servidor.',
                          style: TextStyle(fontSize: 10, color: Colors.white38)),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(6),
                    itemCount: lines.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        lines[i],
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.25,
                          fontFamily: 'monospace',
                          color: _color(lines[i]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _HeaderButton({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, size: 16, color: Colors.white70),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
      );
}
