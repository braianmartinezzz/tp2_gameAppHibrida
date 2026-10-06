import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/player_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';

void main() {
  testWidgets('RunnerGame corre frames, dibuja el mapa y spawnea obstáculos',
      (tester) async {
    final gameState = GameState();
    final game = RunnerGame(gameState: gameState);

    await tester.pumpWidget(GameWidget(game: game));

    // ~1.5 s de juego: cubre el arranque, la animación del mapa y el
    // primer obstáculo (cooldown inicial de 1.1 s).
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // Si el render del mapa o el update lanzaran una excepción, pump la
    // re-lanzaría y el test fallaría acá.
    expect(game.hasLayout, isTrue);
    expect(game.children.whereType<PlayerComponent>(), isNotEmpty);
    expect(
      game.children.whereType<ObstacleComponent>(),
      isNotEmpty,
      reason: 'debería haber spawneado al menos un obstáculo',
    );
    expect(gameState.isGameOver.value, isFalse);

    // Reinicio desde la botonera externa.
    game.restartRun();
    await tester.pump(const Duration(milliseconds: 16));
    expect(gameState.isGameOver.value, isFalse);
    expect(gameState.score.value, 0);
  });

  testWidgets('PlayerComponent carga el SVG del adventurer como art principal',
      (tester) async {
    final gameState = GameState();
    final game = RunnerGame(gameState: gameState);

    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();

    // El arte se carga en background (no bloquea el montaje, ver
    // PlayerComponent.onLoad): acá se espera a que termine. Ese I/O corre en
    // el event loop real, por lo que solo avanza dentro de `runAsync`.
    await tester.runAsync(() => game.player.artReady);
    await tester.pump();

    final player = game.player;
    expect(player.hasCustomArt, isTrue,
        reason: 'debería cargar el SVG del personaje adventurer');
  });
}
