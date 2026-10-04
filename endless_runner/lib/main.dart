import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'state/game_state.dart';
import 'state/settings_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Estado unico compartido por toda la app (usuario ya "logueado" simulado).
  // Los ajustes (tutorial visto, sensibilidad, tema) se cargan antes del
  // primer frame para que no haya parpadeos en usuarios que ya lo hicieron.
  final gameState = GameState(store: SettingsStore());
  await gameState.loadSettings();

  runApp(RunnerApp(gameState: gameState));
}

class RunnerApp extends StatefulWidget {
  const RunnerApp({super.key, required this.gameState});

  final GameState gameState;

  @override
  State<RunnerApp> createState() => _RunnerAppState();
}

class _RunnerAppState extends State<RunnerApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Valor inicial: el canvas de Flame no tiene contexto, así que espejamos
    // el brillo del sistema en el estado desde el arranque.
    widget.gameState.platformBrightness.value =
        ui.PlatformDispatcher.instance.platformBrightness;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // Con tema "Auto", el usuario puede cambiar el modo del celular con la
    // app abierta: el notificador le avisa al juego y a la UI.
    widget.gameState.platformBrightness.value =
        ui.PlatformDispatcher.instance.platformBrightness;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: widget.gameState.themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Runner 2.5D',
          themeMode: mode,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          // Salto suave al alternar claro/oscuro (si no, el cambio es seco).
          themeAnimationDuration: const Duration(milliseconds: 320),
          themeAnimationCurve: Curves.easeInOut,
          home: HomeScreen(gameState: widget.gameState),
        );
      },
    );
  }
}
