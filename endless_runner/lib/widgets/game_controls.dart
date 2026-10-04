import 'package:flutter/material.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'ad_modal.dart';
import 'rewards_modal.dart';

/// Controla el FlameGame desde AFUERA del widget de juego, como pide la consigna.
///
/// Cinco botones "caramelo" con relieve 3D: se hunden al apretarlos.
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
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: _CandyButton(
                  tooltip: 'Inicio',
                  icon: Icons.play_arrow_rounded,
                  label: 'Play',
                  color: AppColors.play,
                  deep: AppColors.playDeep,
                  onPressed: game.resumeGame,
                ),
              ),
              Expanded(
                child: _CandyButton(
                  tooltip: 'Pausa',
                  icon: Icons.pause_rounded,
                  label: 'Pause',
                  color: AppColors.pause,
                  deep: AppColors.pauseDeep,
                  onPressed: game.pauseGame,
                ),
              ),
              Expanded(
                child: _CandyButton(
                  tooltip: 'Reiniciar partida',
                  icon: Icons.replay_rounded,
                  label: 'Reset',
                  color: AppColors.reset,
                  deep: AppColors.resetDeep,
                  onPressed: () => _onRestart(context),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<int>(
                  valueListenable: gameState.claimable,
                  builder: (_, pending, __) => _CandyButton(
                    tooltip: 'Premios',
                    icon: Icons.card_giftcard_rounded,
                    label: 'Premios',
                    color: AppColors.goldDeep,
                    deep: const Color(0xFFB45309),
                    badge: pending,
                    onPressed: () {
                      // Mirar los premios con la partida corriendo sería
                      // injusto: se pausa (si se puede) antes de abrir.
                      game.pauseGame();
                      showRewardsModal(context, gameState);
                    },
                  ),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder<ThemeMode>(
                  valueListenable: gameState.themeMode,
                  builder: (_, mode, __) => _CandyButton(
                    tooltip: 'Modo claro/oscuro',
                    icon: mode == ThemeMode.dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    label: mode == ThemeMode.dark ? 'Dark' : 'Light',
                    color: AppColors.mode,
                    deep: AppColors.modeDeep,
                    onPressed: gameState.toggleTheme,
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

/// Botón con relieve: un "labio" oscuro debajo que desaparece al presionar,
/// como si la tecla se hundiera.
class _CandyButton extends StatefulWidget {
  const _CandyButton({
    required this.tooltip,
    required this.icon,
    required this.label,
    required this.color,
    required this.deep,
    required this.onPressed,
    this.badge = 0,
  });

  final String tooltip;
  final IconData icon;
  final String label;
  final Color color;
  final Color deep;
  final VoidCallback onPressed;

  /// Si es mayor que 0 se dibuja un globito rojo con el número.
  final int badge;

  @override
  State<_CandyButton> createState() => _CandyButtonState();
}

class _CandyButtonState extends State<_CandyButton> {
  static const double _lip = 5;
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onPressed,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              width: 58,
              height: 52,
              margin: EdgeInsets.only(
                top: _pressed ? _lip : 0,
                bottom: _pressed ? 0 : _lip,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(widget.color, Colors.white, 0.22)!,
                    widget.color,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                boxShadow: _pressed
                    ? const []
                    : [
                        BoxShadow(
                          color: widget.deep,
                          offset: const Offset(0, _lip),
                        ),
                      ],
              ),
              child: Icon(widget.icon, size: 30, color: Colors.white),
            ),
                if (widget.badge > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0483C),
                        shape: BoxShape.rectangle,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        '${widget.badge}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              widget.label,
              style: TextStyle(
                color: labelColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
