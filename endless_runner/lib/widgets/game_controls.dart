import 'package:flutter/material.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
import 'ad_modal.dart';

/// Controla el FlameGame desde AFUERA del widget de juego, como pide la consigna.
class GameControls extends StatelessWidget {
  const GameControls({
    super.key,
    required this.game,
    required this.gameState,
  });

  final RunnerGame game;
  final GameState gameState;

  Future<void> _onRestart(BuildContext context) async {
    // Publicidad simulada (modal) antes de reiniciar partida.
    await showAdModal(context);
    game.restartRun();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'Inicio',
            icon: const Icon(Icons.play_arrow),
            onPressed: () => game.resumeEngine(),
          ),
          IconButton(
            tooltip: 'Pausa',
            icon: const Icon(Icons.pause),
            onPressed: () => game.pauseEngine(),
          ),
          IconButton(
            tooltip: 'Reiniciar partida',
            icon: const Icon(Icons.replay),
            onPressed: () => _onRestart(context),
          ),
          IconButton(
            tooltip: 'Modo claro/oscuro',
            icon: ValueListenableBuilder<ThemeMode>(
              valueListenable: gameState.themeMode,
              builder: (_, mode, __) => Icon(
                mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode,
              ),
            ),
            onPressed: gameState.toggleTheme,
          ),
        ],
      ),
    );
  }
}
