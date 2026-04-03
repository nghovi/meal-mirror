import 'package:flutter/material.dart';

import 'pages/auth_page.dart';
import 'pages/home_page.dart';
import 'services/auth_service.dart';

class AnKiengApp extends StatefulWidget {
  const AnKiengApp({super.key});

  @override
  State<AnKiengApp> createState() => _AnKiengAppState();
}

class _AnKiengAppState extends State<AnKiengApp> {
  final AuthService _authService = AuthService.instance;

  @override
  void initState() {
    super.initState();
    _authService.addListener(_handleAuthChanged);
    _authService.loadSession();
  }

  @override
  void dispose() {
    _authService.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    if (mounted) {
      setState(() {});
    }
  }

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
      home: _authService.hasLoaded
          ? (_authService.isAuthenticated
              ? const HomePage()
              : AuthPage(authService: _authService))
          : const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            ),
    );
  }
}
