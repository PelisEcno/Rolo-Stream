import 'package:animeav1_plugin/animeav1_source.dart';
import 'package:jkanime_plugin/jkanime_source.dart';
import 'package:latanime_plugin/latanime_source.dart';
import 'package:rolostream_core/rolostream_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Registro único de fuentes. La primera es la que se activa por defecto.
/// Para agregar una fuente nueva basta con añadirla a esta lista.
final PluginRegistry pluginRegistry = PluginRegistry([
  LatanimeSource(),
  AnimeAV1Source(),
  JKAnimeSource(),
]);

const _prefKey = 'active_source';

/// Restaura la fuente elegida la última vez y guarda cada cambio.
/// Llamar una vez en `main()`, antes de `runApp`.
Future<void> initSourceRegistry() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_prefKey);
  if (saved != null) pluginRegistry.select(saved);
  pluginRegistry.changes.listen((source) => prefs.setString(_prefKey, source.id));
}
