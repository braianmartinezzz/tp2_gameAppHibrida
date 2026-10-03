import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ad_modal.dart';
import '../widgets/game_controls.dart';
import '../widgets/game_header.dart';
import '../widgets/game_over_overlay.dart';
import '../widgets/record_chip.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.gameState});

  final GameState gameState;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final RunnerGame _game;

  @override
  void initState() {
    super.initState();
    _game = RunnerGame(gameState: widget.gameState);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GameHeader(gameState: widget.gameState),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                // Marco con degradé y brillo: el corredor queda "enmarcado"
                // como una pantallita de arcade.
                child: Container(
                  padding: const EdgeInsets.all(3.5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: LinearGradient(
                      colors: [scheme.primary, AppColors.gem, scheme.tertiary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22.5),
                    // El corredor y sus capas de interfaz (récord y resumen)
                    // comparten la misma área: los widgets van encima del
                    // juego, sin tocar el header ni la botonera.
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GameWidget(game: _game),
                        // Récord y diamantes de la corrida, arriba a la
                        // izquierda (el HUD de power-ups ocupa la derecha,
                        // en el canvas).
                        Positioned(
                          top: 10,
                          left: 10,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: widget.gameState.isGameOver,
                            builder: (_, over, __) => over
                                ? const SizedBox.shrink()
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      RecordChip(gameState: widget.gameState),
                                      const SizedBox(height: 6),
                                      _RunDiamondsChip(
                                        gameState: widget.gameState,
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        // Resumen al morir: queda por encima de todo.
                        ValueListenableBuilder<bool>(
                          valueListenable: widget.gameState.isGameOver,
                          builder: (_, over, __) => over
                              ? GameOverOverlay(
                                  gameState: widget.gameState,
                                  onRestart: _restartAfterAd,
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            GameControls(game: _game, gameState: widget.gameState),
          ],
        ),
      ),
    );
  }

  /// Reintento desde el resumen: mismo camino que la botonera externa
  /// (anuncio simulado y después reinicio, requisito de la consigna).
  Future<void> _restartAfterAd() async {
    await showAdModal(context);
    _game.restartRun();
  }
}

/// Diamantes ganados en la corrida actual ("+N"), sobre el corredor.
class _RunDiamondsChip extends StatelessWidget {
  const _RunDiamondsChip({required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 11, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1224).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, size: 15, color: AppColors.gem),
          const SizedBox(width: 5),
          ValueListenableBuilder<int>(
            valueListenable: gameState.runDiamonds,
            builder: (_, runDiamonds, __) => Text(
              '+$runDiamonds',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
