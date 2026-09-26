import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'state/game_state.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(RunnerApp());
}

class RunnerApp extends StatelessWidget {
  RunnerApp({super.key});

  // Estado unico compartido por toda la app (usuario ya "logueado" simulado).
  final GameState gameState = GameState();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: gameState.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Runner 2.5D',
          themeMode: mode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          home: HomeScreen(gameState: gameState),
        );
      },
    );
  }
}
