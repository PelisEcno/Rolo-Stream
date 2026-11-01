import 'package:flutter/material.dart';
import '../../services/favorites_service.dart';
import '../widgets/anime_card.dart';
import 'detail_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mi lista')),
      body: ListenableBuilder(
        listenable: FavoritesService.instance,
        builder: (context, _) {
          final items = FavoritesService.instance.items;
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.bookmark_border_rounded,
              title: 'Tu lista está vacía',
              subtitle: 'Agrega series con el botón de marcador para verlas aquí.',
            );
          }
          return AnimeGrid(
            count: items.length,
            builder: (i) {
              final a = items[i];
              return AnimeCard(
                nombre: a.nombre,
                imagen: a.imagen,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DetailScreen(sourceId: a.sourceId, nombre: a.nombre, url: a.url, imagen: a.imagen)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
