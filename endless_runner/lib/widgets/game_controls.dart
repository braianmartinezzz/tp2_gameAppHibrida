import 'package:flutter/material.dart';

import '../audio/game_sfx.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'ad_modal.dart';
import 'pixel_ui.dart';

/// Controla el FlameGame desde AFUERA del widget de juego, como pide la consigna.
///
/// Cuatro botones de consola en un panel pixel: se hunden al apretarlos. El
/// naranja queda para Jugar (lo principal); el azul noche es el botón de modo.
class GameControls extends StatelessWidget {
  const GameControls({
    super.key,
    required this.game,
    required this.gameState,
  });

  final RunnerGame game;
  final GameState gameState;

  Future<void> _onRestart(BuildContext context) async {
    // Publicidad simulada (modal) antes de reiniciar partida; la cuenta Pro
    // la saltea.
    await showInterstitialAd(context, gameState);
    game.restartRun();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: CustomPaint(
        painter: PixelPanelPainter(
          fill: isDark ? AppColors.headerDark : AppColors.headerLight,
          border: PixelStyle.ink,
          edge: isDark ? PixelStyle.panelEdge : const Color(0xFF7A5434),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: _CandyButton(
                  tooltip: 'Jugar o continuar',
                  icon: Icons.play_arrow_rounded,
                  label: 'Jugar',
                  color: AppColors.ctrlPlay,
                  deep: AppColors.ctrlPlayDeep,
                  onPressed: game.resumeGame,
                ),
              ),
              Expanded(
                child: _CandyButton(
                  tooltip: 'Pausa',
                  icon: Icons.pause_rounded,
                  label: 'Pausa',
                  color: AppColors.ctrlPause,
                  deep: AppColors.ctrlPauseDeep,
                  onPressed: game.pauseGame,
                ),
              ),
              Expanded(
                child: _CandyButton(
                  tooltip: 'Reiniciar partida',
                  icon: Icons.replay_rounded,
                  label: 'Reiniciar',
                  color: AppColors.ctrlReset,
                  deep: AppColors.ctrlResetDeep,
                  onPressed: sfxCallback(() => _onRestart(context)),
                ),
              ),
              Expanded(
                // Auto → Claro → Oscuro → Auto. El icono y el rótulo cuentan
                // el modo elegido (no el brillo resuelto): en "Auto" el
                // aspecto real puede ser cualquiera de los dos.
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: gameState.themeMode,
                  builder: (_, mode, __) => _CandyButton(
                    tooltip: switch (mode) {
                      ThemeMode.system => 'Tema: automático (sistema)',
                      ThemeMode.light => 'Tema: claro',
                      ThemeMode.dark => 'Tema: oscuro',
                    },
                    icon: switch (mode) {
                      ThemeMode.system => Icons.brightness_auto_rounded,
                      ThemeMode.light => Icons.light_mode_rounded,
                      ThemeMode.dark => Icons.dark_mode_rounded,
                    },
                    label: switch (mode) {
                      ThemeMode.system => 'Auto',
                      ThemeMode.light => 'Claro',
                      ThemeMode.dark => 'Oscuro',
                    },
                    color: AppColors.mode,
                    deep: AppColors.modeDeep,
                    onPressed: sfxCallback(gameState.cycleTheme, sfx: Sfx.toggle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Botón pixel de la botonera: ícono en tinta oscura sobre un color claro
/// (contraste ≥ 4.5:1) y rótulo en la fuente pixel debajo. Al apretarlo se
/// hunde un píxel (lo resuelve [PixelButton]).
class _CandyButton extends StatelessWidget {
  const _CandyButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.color,
    required this.deep,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final Color color;
  final Color deep;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PixelButton(
            // Sin sonido propio: el que corresponde lo pone quien lo recibe
            // (pausa/continuar suenan desde RunnerGame; el resto con sfxTap).
            sfx: null,
            onTap: onPressed,
            semanticLabel: tooltip,
            padding: EdgeInsets.zero,
            fill: [Color.lerp(color, Colors.white, 0.28)!, color],
            border: PixelStyle.ink,
            edge: deep,
            child: SizedBox(
              width: 58,
              height: 50,
              child: Center(
                child: Icon(icon, size: 30, color: AppColors.ink),
              ),
            ),
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: PixelStyle.text(8, color: PixelStyle.cream, height: 1.0),
            ),
          ),
        ],
      ),
    );
  }
}
