import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/screens/home_screen.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/settings_store.dart';

/// Store en memoria: registra lo último que se guardó.
class _FakeStore extends SettingsStore {
  _FakeStore({this.initial});

  final Map<String, dynamic>? initial;
  Map<String, dynamic>? saved;
  int saves = 0;

  @override
  Future<Map<String, dynamic>?> load() async => initial;

  @override
  Future<void> save(Map<String, dynamic> data) async {
    saved = data;
    saves++;
  }
}

class _BrokenStore extends SettingsStore {
  @override
  Future<Map<String, dynamic>?> load() async => throw Exception('sin disco');

  @override
  Future<void> save(Map<String, dynamic> data) async =>
      throw Exception('sin disco');
}

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GameState: ajustes', () {
    test('la sensibilidad se limita al rango y se guarda', () {
      final store = _FakeStore();
      final state = GameState(store: store);

      state.setSwipeSensitivity(9);
      expect(state.swipeSensitivity.value, GameState.maxSensitivity);
      state.setSwipeSensitivity(0.01);
      expect(state.swipeSensitivity.value, GameState.minSensitivity);
      state.setSwipeSensitivity(1.5);
      expect(state.swipeSensitivity.value, 1.5);
      expect(store.saved?['swipeSensitivity'], 1.5);
    });

    test('markTutorialSeen guarda una sola vez', () {
      final store = _FakeStore();
      final state = GameState(store: store);

      expect(state.tutorialSeen.value, isFalse);
      state.markTutorialSeen();
      state.markTutorialSeen();
      expect(state.tutorialSeen.value, isTrue);
      expect(store.saves, 1);
      expect(store.saved?['tutorialSeen'], isTrue);
    });

    test('loadSettings aplica lo guardado y tolera un store roto', () async {
      final loaded = GameState(
        store: _FakeStore(
          initial: {'tutorialSeen': true, 'swipeSensitivity': 1.75},
        ),
      );
      await loaded.loadSettings();
      expect(loaded.tutorialSeen.value, isTrue);
      expect(loaded.swipeSensitivity.value, 1.75);

      final broken = GameState(store: _BrokenStore());
      await broken.loadSettings(); // no lanza
      expect(broken.tutorialSeen.value, isFalse);
      expect(broken.swipeSensitivity.value, GameState.defaultSensitivity);
      broken.setSwipeSensitivity(1.25); // tampoco lanza al guardar
      await Future<void>.delayed(Duration.zero);
    });

    test('resetRun saca la pausa', () {
      final state = GameState()..isPaused.value = true;
      state.resetRun();
      expect(state.isPaused.value, isFalse);
    });
  });

  group('RunnerGame: sensibilidad', () {
    test('el umbral del gesto se acorta al subir la sensibilidad', () {
      final state = GameState();
      final game = RunnerGame(gameState: state);

      expect(game.swipeThreshold, closeTo(22, 0.001));
      state.setSwipeSensitivity(2);
      expect(game.swipeThreshold, closeTo(11, 0.001));
      state.setSwipeSensitivity(0.5);
      expect(game.swipeThreshold, closeTo(44, 0.001));
    });
  });

  group('RunnerGame: pausa', () {
    testWidgets('pausa congela el mundo y bloquea los gestos', (tester) async {
      final state = GameState();
      final game = RunnerGame(gameState: state);
      await tester.pumpWidget(GameWidget(game: game));
      await _pumpFrames(tester, 30);
      expect(state.score.value, greaterThan(0));

      game.pauseGame();
      expect(state.isPaused.value, isTrue);

      final frozenScore = state.score.value;
      await tester.drag(
        find.byType(GameWidget<RunnerGame>),
        const Offset(90, 0),
      );
      await _pumpFrames(tester, 30);
      expect(state.score.value, frozenScore, reason: 'el score no corre');
      expect(game.player.lane, 0, reason: 'los gestos no mueven en pausa');

      game.resumeGame();
      expect(state.isPaused.value, isFalse);
      await _pumpFrames(tester, 30);
      expect(state.score.value, greaterThan(frozenScore));
    });

    testWidgets('no se puede pausar en tutorial ni con la partida terminada',
        (tester) async {
      final state = GameState();
      final game = RunnerGame(gameState: state);
      await tester.pumpWidget(GameWidget(game: game));
      await _pumpFrames(tester, 5);

      game.tutorialActive = true;
      game.pauseGame();
      expect(state.isPaused.value, isFalse);

      game.tutorialActive = false;
      state.finishRun();
      game.pauseGame();
      expect(state.isPaused.value, isFalse);
    });
  });

  group('RunnerGame: modo tutorial', () {
    testWidgets('sin obstáculos ni score, y el corredor responde al gesto',
        (tester) async {
      final state = GameState();
      final game = RunnerGame(gameState: state)..tutorialActive = true;
      final actions = <RunnerAction>[];
      game.onAction = actions.add;
      await tester.pumpWidget(GameWidget(game: game));

      await _pumpFrames(tester, 120); // ~2 s: en juego normal ya habría obstáculos
      expect(game.children.whereType<ObstacleComponent>(), isEmpty);
      expect(state.score.value, 0);

      await tester.drag(
        find.byType(GameWidget<RunnerGame>),
        const Offset(0, -90),
      );
      await tester.pump(const Duration(milliseconds: 30));
      expect(game.player.isAirborne, isTrue);
      expect(actions, [RunnerAction.jump]);
    });
  });

  group('HomeScreen', () {
    testWidgets('tutorial de la primera vez: gestos, información y cierre',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final state = GameState()..themeMode.value = ThemeMode.dark;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(gameState: state)));
      await _pumpFrames(tester, 40);

      expect(find.text('Deslizá hacia arriba'), findsOneWidget);
      expect(state.tutorialSeen.value, isFalse);

      // Paso 1: un gesto equivocado no avanza.
      await tester.drag(
        find.byType(GameWidget<RunnerGame>),
        const Offset(0, 90),
      );
      await _pumpFrames(tester, 10);
      expect(find.text('Deslizá hacia arriba'), findsOneWidget);

      // Esperar a que el corredor vuelva a estar parado y saltar.
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(
        find.byType(GameWidget<RunnerGame>),
        const Offset(0, -90),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('¡Bien!'), findsOneWidget);

      // Paso 2.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Deslizá hacia abajo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(
        find.byType(GameWidget<RunnerGame>),
        const Offset(0, 90),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('¡Bien!'), findsOneWidget);

      // Paso 3: a la izquierda.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Deslizá a la izquierda'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(
        find.byType(GameWidget<RunnerGame>),
        const Offset(-90, 0),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('¡Bien!'), findsOneWidget);

      // Paso 4: a la derecha.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Deslizá a la derecha'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(
        find.byType(GameWidget<RunnerGame>),
        const Offset(90, 0),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('¡Bien!'), findsOneWidget);

      // Pasos informativos: diamantes y corazones, power-ups, peligros.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Diamantes y corazones'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Power-ups'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Cuidado con el camino'), findsOneWidget);
      expect(find.text('¡Entendido!'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tutorial-next')));
      await tester.pump(const Duration(milliseconds: 400));

      // Cierre: "¡Listo!", y se recuerda que ya se vio.
      expect(find.text('¡Listo, a correr!'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('¡Listo, a correr!'), findsNothing);
      expect(state.tutorialSeen.value, isTrue);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('"Saltar tutorial" lo cierra y lo marca como visto',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final state = GameState();
      await tester.pumpWidget(MaterialApp(home: HomeScreen(gameState: state)));
      await _pumpFrames(tester, 40);

      await tester.tap(find.text('Saltar tutorial'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Saltar tutorial'), findsNothing);
      expect(state.tutorialSeen.value, isTrue);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('pausa: overlay, sensibilidad y cuenta regresiva al continuar',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final state = GameState()
        ..themeMode.value = ThemeMode.dark
        ..tutorialSeen.value = true;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(gameState: state)));
      await _pumpFrames(tester, 40);
      expect(find.text('PAUSA'), findsNothing);

      await tester.tap(find.byTooltip('Pausar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.isPaused.value, isTrue);
      expect(find.text('PAUSA'), findsOneWidget);
      expect(find.text('Normal · desliz de 22 px'), findsOneWidget);

      state.setSwipeSensitivity(2);
      await tester.pump();
      expect(find.text('Alta · desliz de 11 px'), findsOneWidget);

      // Continuar: 3 - 2 - 1 y recién ahí se reanuda.
      await tester.tap(find.text('Continuar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('3'), findsOneWidget);
      expect(state.isPaused.value, isTrue);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('2'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('1'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 700));
      expect(state.isPaused.value, isFalse);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('PAUSA'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
