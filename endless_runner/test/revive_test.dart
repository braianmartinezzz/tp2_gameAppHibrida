import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/chase_horde.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/rewards.dart';
import 'package:runner_flutter/widgets/game_over_overlay.dart';

void main() {
  group('GameState: revivir', () {
    test('revive reanuda la misma partida con una vida', () {
      final state = GameState();
      state.addScore(300);
      state.collectDiamond(3);
      state.finishRun();
      expect(state.canRevive, isTrue);

      expect(state.revive(), isTrue);
      expect(state.isGameOver.value, isFalse);
      expect(state.lives.value, 1);
      expect(state.score.value, 300, reason: 'el puntaje se conserva');
      expect(state.runDiamonds.value, 3);
      expect(state.canRevive, isFalse);
    });

    test('solo se puede revivir una vez por partida', () {
      final state = GameState();
      state.finishRun();
      expect(state.revive(), isTrue);

      state.finishRun();
      expect(state.canRevive, isFalse);
      expect(state.revive(), isFalse);
      expect(state.isGameOver.value, isTrue);

      state.resetRun();
      state.finishRun();
      expect(state.canRevive, isTrue, reason: 'partida nueva, revivir nuevo');
    });

    test('no se puede revivir si la partida no terminó', () {
      final state = GameState();
      expect(state.revive(), isFalse);
      expect(state.revivedThisRun, isFalse);
    });

    test('el récord no se celebra dos veces ni la partida cuenta doble', () {
      final state = GameState();
      state.addScore(100);
      state.finishRun();
      expect(state.isNewRecord.value, isTrue);

      state.revive();
      expect(state.bestScore.value, 0, reason: 'se restaura el récord previo');
      expect(state.isNewRecord.value, isFalse);

      state.addScore(50);
      state.finishRun();
      expect(state.bestScore.value, 150);
      expect(state.isNewRecord.value, isTrue);
    });

    test('una partida revivida cuenta una sola vez para los desafíos', () {
      final state = GameState();
      final runs = state.challenges
          .where((c) => c.metric == ChallengeMetric.runs)
          .toList();
      if (runs.isEmpty) return; // el desafío de partidas no salió hoy

      state.finishRun();
      state.revive();
      state.finishRun();
      expect(state.challengeProgress(runs.first), 1);
    });
  });

  group('ChaseHorde: revivir', () {
    test('revive deja de atrapar al jugador y conserva el nivel', () {
      final horde = ChaseHorde();
      horde.update(25); // sube de nivel
      final level = horde.level;
      horde.gap = 0;
      horde.caught = true;

      horde.revive();
      expect(horde.caught, isFalse);
      expect(horde.gap, ChaseHorde.reviveGap);
      expect(horde.level, level);
    });
  });

  group('GameOverOverlay: botón de revivir', () {
    Future<void> pump(WidgetTester tester, GameState state,
        {VoidCallback? onRevive}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameOverOverlay(
            gameState: state,
            onRestart: () {},
            onRevive: onRevive,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('cuenta basic: ofrece revivir viendo un anuncio',
        (tester) async {
      final state = GameState()..finishRun();
      var taps = 0;
      await pump(tester, state, onRevive: () => taps++);

      expect(find.text('Revivir viendo un anuncio'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('revive-button')));
      expect(taps, 1);
    });

    testWidgets('cuenta Pro: revivir gratis, sin anuncio', (tester) async {
      final state = GameState()
        ..toggleAccountType()
        ..finishRun();
      await pump(tester, state, onRevive: () {});

      expect(find.text('Revivir gratis (Pro)'), findsOneWidget);
    });

    testWidgets('si ya se revivió, el botón no aparece', (tester) async {
      final state = GameState()..finishRun();
      state.revive();
      state.finishRun();
      await pump(tester, state, onRevive: () {});

      expect(find.byKey(const ValueKey('revive-button')), findsNothing);
    });
  });
}
