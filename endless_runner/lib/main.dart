import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'state/game_state.dart';
import 'state/settings_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Estado unico compartido por toda la app (usuario ya "logueado" simulado).
  // Los ajustes (tutorial visto, sensibilidad) se cargan antes del primer
  // frame para que el tutorial no parpadee en usuarios que ya lo hicieron.
  final gameState = GameState(store: SettingsStore());
  await gameState.loadSettings();

  runApp(RunnerApp(gameState: gameState));
}

class RunnerApp extends StatelessWidget {
  const RunnerApp({super.key, required this.gameState});

  final GameState gameState;

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
