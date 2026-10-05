import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/screens/home_screen.dart';
import 'package:runner_flutter/screens/start_screen.dart';
import 'package:runner_flutter/state/game_state.dart';

void main() {
  /// Monta la pantalla de inicio con el tamaño de pantalla pedido. El botón
  /// JUGAR late sin parar, así que se usa `pump` y nunca `pumpAndSettle`.
  Future<GameState> pumpStart(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    GameState? state,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gameState = state ?? GameState();
    await tester.pumpWidget(
      MaterialApp(home: StartScreen(gameState: gameState)),
    );
    await tester.pump();
    return gameState;
  }

  group('StartScreen', () {
    testWidgets('muestra JUGAR, LOGROS y RÉCORD en un celular vertical', (
      tester,
    ) async {
      await pumpStart(tester);

      expect(find.text('JUGAR'), findsOneWidget);
      expect(find.text('LOGROS'), findsOneWidget);
      expect(find.text('RÉCORD'), findsOneWidget);
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
      expect(find.text('85'), findsOneWidget); // billetera de diamantes
    });

    testWidgets('se acomoda en pantallas apaisadas y chicas sin desbordar', (
      tester,
    ) async {
      for (final size in const [
        Size(1280, 720),
        Size(360, 640),
        Size(768, 1024),
      ]) {
        await pumpStart(tester, size: size);
        expect(find.text('JUGAR'), findsOneWidget, reason: '$size');
        expect(tester.takeException(), isNull, reason: '$size');
      }
    });

    testWidgets('RÉCORD muestra el mejor puntaje', (tester) async {
      final state = GameState()..bestScore.value = 1234;
      await pumpStart(tester, state: state);

      await tester.tap(find.text('RÉCORD'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('PUNTAJE MÁXIMO'), findsOneWidget);
      expect(find.text('1234'), findsOneWidget);
    });

    testWidgets('AJUSTES cambia el tema y la sensibilidad', (tester) async {
      final state = GameState();
      await pumpStart(tester, state: state);

      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('AJUSTES'), findsOneWidget);
      expect(find.text('SENSIBILIDAD'), findsOneWidget);
      expect(find.text('TEMA'), findsOneWidget);

      await tester.tap(find.text('NOCHE'));
      await tester.pump();
      expect(state.themeMode.value, ThemeMode.dark);

      await tester.tap(find.text('DÍA'));
      await tester.pump();
      expect(state.themeMode.value, ThemeMode.light);
    });

    testWidgets('LOGROS avisa con un globito cuando hay premios', (
      tester,
    ) async {
      final state = GameState();
      await pumpStart(tester, state: state);
      expect(find.text('3'), findsNothing);

      state.claimable.value = 3;
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('JUGAR abre el juego con una partida limpia', (tester) async {
      final state = GameState()
        ..score.value = 99
        ..isGameOver.value = true;
      await pumpStart(tester, state: state);

      await tester.tap(find.text('JUGAR'));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(state.score.value, 0);
      expect(state.isGameOver.value, isFalse);
    });
  });
}
