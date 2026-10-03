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
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ControlPill(
              tooltip: 'Inicio',
              icon: Icons.play_arrow_rounded,
              label: 'Play',
              onPressed: () => game.resumeEngine(),
              color: theme.colorScheme.primary,
            ),
            _ControlPill(
              tooltip: 'Pausa',
              icon: Icons.pause_rounded,
              label: 'Pause',
              onPressed: () => game.pauseEngine(),
              color: theme.colorScheme.secondary,
            ),
            _ControlPill(
              tooltip: 'Reiniciar partida',
              icon: Icons.replay_rounded,
              label: 'Reset',
              onPressed: () => _onRestart(context),
              color: theme.colorScheme.tertiary,
            ),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: gameState.themeMode,
              builder: (_, mode, __) => _ControlPill(
                tooltip: 'Modo claro/oscuro',
                icon: mode == ThemeMode.dark
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                label: mode == ThemeMode.dark ? 'Dark' : 'Light',
                onPressed: gameState.toggleTheme,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: color.withValues(alpha: 0.12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
