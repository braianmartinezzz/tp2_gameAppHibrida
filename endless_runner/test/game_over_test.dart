import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/screens/home_screen.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/widgets/game_over_overlay.dart';
import 'package:runner_flutter/widgets/record_chip.dart';

void main() {
  group('GameState: récord y resumen', () {
    test('el récord solo cambia al superarlo y sobrevive a los reinicios', () {
      final state = GameState();

      state.addScore(100);
      state.finishRun();
      expect(state.isGameOver.value, isTrue);
      expect(state.bestScore.value, 100);
      expect(state.isNewRecord.value, isTrue);

      state.resetRun();
      expect(state.isNewRecord.value, isFalse, reason: 'la medalla es de una corrida');
      expect(state.bestScore.value, 100, reason: 'el récord no se pierde al reiniciar');

      state.addScore(60);
      state.finishRun();
      expect(state.bestScore.value, 100, reason: 'un score menor no lo baja');
      expect(state.isNewRecord.value, isFalse);

      state.resetRun();
      state.addScore(250);
      state.finishRun();
      expect(state.bestScore.value, 250);
      expect(state.isNewRecord.value, isTrue);
    });

    test('finishRun no se pisa si la partida ya terminó', () {
      final state = GameState();
      state.addScore(100);
      state.finishRun();
      expect(state.isNewRecord.value, isTrue);

      // Un segundo llamado (colisión doble, código raro) no reescribe el
      // resultado que ya se mostró en el resumen.
      state.addScore(999);
      state.finishRun();
      expect(state.bestScore.value, 100);
      expect(state.isNewRecord.value, isTrue);
    });

    test('collectDiamond suma a billetera y partida; resetRun solo limpia la corrida',
        () {
      final state = GameState();
      state
        ..collectDiamond()
        ..collectDiamond();
      expect(state.diamonds.value, 87);
      expect(state.runDiamonds.value, 2);

      // Gastar (tienda o golpe pagado) mueve la billetera, no lo ganado.
      state.spendDiamonds(50);
      expect(state.diamonds.value, 37);
      expect(state.runDiamonds.value, 2);

      state.resetRun();
      expect(state.runDiamonds.value, 0, reason: 'la corrida arranca de cero');
      expect(state.diamonds.value, 37, reason: 'lo recolectado queda cobrado');
    });
  });

  group('overlay de fin de partida', () {
    testWidgets('el chip sigue al mejor puntaje', (tester) async {
      final state = GameState()..bestScore.value = 500;
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RecordChip(gameState: state))),
      );

      expect(find.text('Récord 500'), findsOneWidget);

      state.bestScore.value = 750;
      await tester.pump();
      expect(find.text('Récord 750'), findsOneWidget);
      expect(find.text('Récord 500'), findsNothing);
    });

    testWidgets(
        'el resumen celebra el nuevo récord con puntaje, récord y diamantes',
        (tester) async {
      final state = GameState()
        ..score.value = 120
        ..runDiamonds.value = 7;
      state.bestScore.value = 90;
      state.finishRun();

      var restarted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameOverOverlay(
              gameState: state,
              onRestart: () => restarted++,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300)); // animación de entrada

      expect(find.text('PARTIDA TERMINADA'), findsOneWidget);
      expect(find.text('Puntaje'), findsOneWidget);
      expect(find.text('Récord'), findsOneWidget);
      expect(
        find.text('120'),
        findsNWidgets(2),
        reason: 'puntaje final = récord recién batido (120 > 90)',
      );
      expect(find.text('90'), findsNothing, reason: 'el récord ya se actualizó');
      expect(find.text('¡NUEVO RÉCORD!'), findsOneWidget, reason: '120 > 90');
      expect(find.text('Ganaste 7 diamantes'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      expect(restarted, 1);
    });

    testWidgets('sin récord nuevo no aparece la medalla', (tester) async {
      final state = GameState()..score.value = 50;
      state.bestScore.value = 90;
      state.finishRun();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GameOverOverlay(gameState: state, onRestart: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('¡NUEVO RÉCORD!'), findsNothing);
      expect(find.text('90'), findsOneWidget, reason: 'el récord se mantiene');
      expect(state.bestScore.value, 90);
      expect(state.isNewRecord.value, isFalse);
    });

    testWidgets(
        'en HomeScreen: chip jugando, resumen al morir y reinicio con anuncio',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final state = GameState()
        ..themeMode.value = ThemeMode.dark
        ..tutorialSeen.value = true // sin tutorial: este test es del resumen
        ..bestScore.value = 500;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(gameState: state)));

      // Un rato de juego: el chip de récord acompaña sobre el corredor.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Récord 500'), findsOneWidget, reason: 'chip visible');
      expect(find.text('PARTIDA TERMINADA'), findsNothing);

      // Fin de partida con récord nuevo (900 > 500).
      state.score.value = 900;
      state.runDiamonds.value = 7;
      state.finishRun();
      await tester.pump(); // arranca la entrada del overlay
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('PARTIDA TERMINADA'), findsOneWidget);
      expect(
        find.text('900'),
        findsNWidgets(2),
        reason: 'puntaje final = nuevo récord',
      );
      expect(find.text('Récord 500'), findsNothing, reason: 'el chip se oculta');
      expect(find.text('¡NUEVO RÉCORD!'), findsOneWidget);
      expect(find.text('Ganaste 7 diamantes'), findsOneWidget);
      expect(state.isNewRecord.value, isTrue);

      // Reintentar pasa por el anuncio simulado antes de reiniciar.
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250)); // anima el modal
      expect(find.text('Anuncio simulado'), findsOneWidget);
      expect(
        state.isGameOver.value,
        isTrue,
        reason: 'recién reinicia después del anuncio',
      );

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1)); // cuenta regresiva (3 s)
      }
      expect(find.text('Cerrar'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300)); // sale el overlay

      expect(find.text('Anuncio simulado'), findsNothing);
      expect(find.text('PARTIDA TERMINADA'), findsNothing);
      expect(state.isGameOver.value, isFalse);
      expect(
        state.score.value,
        lessThan(10),
        reason: 'la corrida arrancó de cero y solo corrió el frame de salida',
      );
      expect(state.runDiamonds.value, 0);
      expect(state.bestScore.value, 900, reason: 'el récord quedó');
      expect(
        find.text('Récord 900'),
        findsOneWidget,
        reason: 'el chip ya muestra el récord nuevo',
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('morir en la partida real actualiza el récord', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final state = GameState()
        ..themeMode.value = ThemeMode.dark
        ..lives.value = 1; // última vida: el primer golpe termina la partida
      final game = RunnerGame(gameState: state);
      await tester.pumpWidget(GameWidget(game: game));

      for (var i = 0; i < 1500 && !state.isGameOver.value; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(state.isGameOver.value, isTrue, reason: 'el primer golpe mata');
      expect(state.score.value, greaterThan(0), reason: 'el score ya corrió');
      expect(
        state.bestScore.value,
        state.score.value,
        reason: 'primer récord de la sesión',
      );
      expect(state.isNewRecord.value, isTrue);

      final record = state.bestScore.value;
      game.restartRun();
      await tester.pump(const Duration(milliseconds: 16));
      expect(state.isGameOver.value, isFalse);
      expect(state.isNewRecord.value, isFalse);
      expect(state.bestScore.value, record, reason: 'el récord no se pierde');
      await tester.binding.setSurfaceSize(null);
    });
  });
}
