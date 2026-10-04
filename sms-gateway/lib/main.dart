import 'package:flutter/material.dart';

import 'screens/dashboard_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.live = true});

  /// False in widget tests, which have no SMS radio, plugins or network.
  final bool live;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Umurima AI Gateway',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: DashboardScreen(live: live),
    );
  }
}
