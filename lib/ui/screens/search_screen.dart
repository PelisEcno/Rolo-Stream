import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../core/plugin_runtime.dart';
import '../../models/anime_result.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  PluginRuntime? _runtime;
  List<AnimeResult> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPlugin();
  }

  Future<void> _loadPlugin() async {
    final code = await rootBundle.loadString('assets/plugins/latanime.js');
    setState(() {
      _runtime = PluginRuntime(code);
    });
  }

  Future<void> _search() async {
    final q = _controller.text.trim();
    if (q.length < 3 || _runtime == null) return;

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      final results = await _runtime!.search(q);
      setState(() => _results = results);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RoloStream - Latanime')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: 'Buscar anime (mín. 3 letras)',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
              ),
              onSubmitted: (_) => _search(),
            ),
          ),
          if (_loading) const CircularProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: _results.isEmpty && !_loading
                ? const Center(child: Text('Escribe y busca'))
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final a = _results[i];
                      return ListTile(
                        leading: a.imagen.isNotEmpty
                            ? Image.network(a.imagen, width: 50, height: 70, fit: BoxFit.cover)
                            : const Icon(Icons.image),
                        title: Text(a.nombre),
                        subtitle: Text('${a.estado} · ${a.categoria}'),
                        onTap: () {
                          // TODO: ir a detalle del anime
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}