import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/widgets/pixel_transition.dart';

/// Transición pixel entre el inicio y el juego + arranque suave del corredor.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('telón de bloques', () {
    test('tapa en la primera mitad y descubre en la segunda', () {
      double c(double t) => PixelCurtainPainter.coverage(t);
      expect(c(0), 0);
      expect(c(0.25), closeTo(0.5, 1e-9));
      expect(c(PixelDissolveRoute.revealAt), 1);
      expect(c(0.75), closeTo(0.5, 1e-9));
      expect(c(1), 0);
    });

    testWidgets('la pantalla nueva aparece recién con el telón cerrado',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                PixelDissolveRoute<void>(
                  builder: (_) => const Scaffold(body: Text('DESTINO')),
                ),
              ),
              child: const Text('IR'),
            ),
          ),
        ),
      );

      double opacidad() => tester
          .widget<Opacity>(find.byKey(const ValueKey('pixel-dissolve-page')))
          .opacity;

      await tester.tap(find.text('IR'));
      await tester.pump(); // arranca la ruta
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('DESTINO'), findsOneWidget); // ya construida...
      expect(opacidad(), 0); // ...pero tapada

      await tester.pump(const Duration(milliseconds: 400)); // pasa la mitad
      expect(opacidad(), 1);

      await tester.pumpAndSettle();
      expect(opacidad(), 1);
    });
  });

  group('arranque suave del corredor', () {
    Future<RunnerGame> montar(WidgetTester tester, GameState state) async {
      final game = RunnerGame(
        gameState: state,
        hordeEnabled: false,
        zombiesEnabled: false,
        trucksEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));
      return game;
    }

    testWidgets('espera quieto hasta launch(): sin puntaje', (tester) async {
      final state = GameState();
      final game = await montar(tester, state);
      game.prepareLaunch();

      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.isLaunching, isTrue);
      expect(state.score.value, 0);
    });

    testWidgets('tras launch() acelera y en ~1 s ya juega normal',
        (tester) async {
      final state = GameState();
      final game = await montar(tester, state);
      game.prepareLaunch();
      await tester.pump(const Duration(milliseconds: 16));

      game.launch();
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.isLaunching, isFalse);

      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(state.score.value, greaterThan(0));
    });

    testWidgets('reiniciar no deja el arranque colgado', (tester) async {
      final game = await montar(tester, GameState());
      game.prepareLaunch();
      game.restartRun();
      expect(game.isLaunching, isFalse);
    });
  });
}
