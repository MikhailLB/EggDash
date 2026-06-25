import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

class EggDashApp extends StatelessWidget {
  const EggDashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Egg Dash',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E1430),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB300),
          secondary: Color(0xFF66BB6A),
          surface: Color(0xFF1B2347),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}
