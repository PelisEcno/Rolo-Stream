import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoriteAnime {
  final String nombre;
  final String url;
  final String imagen;

  const FavoriteAnime({required this.nombre, required this.url, required this.imagen});

  Map<String, dynamic> toJson() => {'nombre': nombre, 'url': url, 'imagen': imagen};

  factory FavoriteAnime.fromJson(Map<String, dynamic> j) => FavoriteAnime(
        nombre: j['nombre'] ?? '',
        url: j['url'] ?? '',
        imagen: j['imagen'] ?? '',
      );
}

/// Favoritos persistidos en shared_preferences. Notifica cambios a la UI.
class FavoritesService extends ChangeNotifier {
  FavoritesService._();
  static final instance = FavoritesService._();
  static const _key = 'favorites';

  final List<FavoriteAnime> _items = [];
  List<FavoriteAnime> get items => List.unmodifiable(_items);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    _items
      ..clear()
      ..addAll(raw.map((e) => FavoriteAnime.fromJson(jsonDecode(e))));
    notifyListeners();
  }

  bool isFavorite(String url) => _items.any((e) => e.url == url);

  Future<void> toggle(FavoriteAnime anime) async {
    if (isFavorite(anime.url)) {
      _items.removeWhere((e) => e.url == anime.url);
    } else {
      _items.insert(0, anime);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, _items.map((e) => jsonEncode(e.toJson())).toList());
  }

  Future<void> clear() async {
    _items.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
