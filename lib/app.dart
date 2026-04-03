import 'package:flutter/material.dart';

import 'pages/home_page.dart';

class AnKiengApp extends StatelessWidget {
  const AnKiengApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFB85C38),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Meal Mirror',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F1EA),
        useMaterial3: true,
        textTheme: Typography.blackCupertino,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: colorScheme.onSurface,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
      home: const HomePage(),
    );
  }
}
