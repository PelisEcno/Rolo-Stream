import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'services/favorites_service.dart';
import 'services/http_client.dart';
import 'services/mediaflow_service.dart';
import 'ui/screens/home_shell.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await HttpClientService.instance.init();
  await MediaFlowService.start();
  await FavoritesService.instance.load();
  runApp(const RoloStreamApp());
}

class RoloStreamApp extends StatelessWidget {
  const RoloStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoloStream',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeShell(),
    );
  }
}
