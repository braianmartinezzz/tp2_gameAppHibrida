import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            GameHeader(gameState: widget.gameState),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  // El corredor y sus capas de interfaz (récord y resumen)
                  // comparten la misma área: los widgets van encima del
                  // juego, sin tocar el header ni la botonera.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      GameWidget(game: _game),
                      // Récord mientras se corre, arriba a la izquierda (el
                      // HUD de power-ups ocupa la derecha, en el canvas).
                      Positioned(
                        top: 10,
                        left: 10,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: widget.gameState.isGameOver,
                          builder: (_, over, __) => over
                              ? const SizedBox.shrink()
                              : RecordChip(gameState: widget.gameState),
                        ),
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: widget.gameState.isGameOver,
                          builder: (_, over, __) => over
                              ? const SizedBox.shrink()
                              : Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.24),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.diamond_rounded,
                                        size: 14,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                      const SizedBox(width: 4),
                                      ValueListenableBuilder<int>(
                                        valueListenable:
                                            widget.gameState.runDiamonds,
                                        builder: (_, runDiamonds, __) => Text(
                                          '+$runDiamonds',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
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
