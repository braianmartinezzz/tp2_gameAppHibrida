import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
import '../widgets/game_controls.dart';
import '../widgets/game_header.dart';

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
                  child: GameWidget(game: _game),
                ),
              ),
            ),
            GameControls(game: _game, gameState: widget.gameState),
          ],
        ),
      ),
    );
  }
}
