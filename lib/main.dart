import 'package:flutter/material.dart';
import 'services/http_client.dart';
import 'ui/screens/search_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HttpClientService.instance.init();
  runApp(const RoloStreamApp());
}

class RoloStreamApp extends StatelessWidget {
  const RoloStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoloStream',
      theme: ThemeData.dark(useMaterial3: true),
      home: const SearchScreen(),
    );
  }
}