import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/power_up_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/game/zombie_obstacle.dart';
import 'package:runner_flutter/haptics/game_haptics.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/settings_store.dart';

/// Doble de [GameHaptics]: no vibra nada y anota qué cue mandó el juego,
/// para poder afirmar la política de vibración sin tocar hardware.
class _FakeHaptics extends GameHaptics {
  final List<HapticCue> cues = [];

  @override
  Future<void> play(HapticCue cue) async => cues.add(cue);
}

/// Piloto automático: se planta en el carril del próximo obstáculo fijo hasta
/// que [stop] se cumple (o se rinde pasados [maxFrames] frames).
///
/// Es el mismo truco que usa `gameplay_test.dart` para el choque end-to-end.
///
/// Antes de arrancar deja correr I/O real un instante (`runAsync`): Flame no
/// monta los componentes hasta que termina la carga de assets del corredor
/// (SVG) y, como los tests corren en fake-async, esa promesa nunca se
/// resolvía y el árbol quedaba vacío (obstáculos que no se mueven y no
/// chocan). Con el desbloqueo, los obstáculos spawnean y avanzan.
Future<void> _driveIntoObstacle(
  WidgetTester tester,
  RunnerGame game,
  bool Function() stop, {
  int maxFrames = 4000,
}) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump(const Duration(milliseconds: 16));

  for (var i = 0; i < maxFrames && !stop(); i++) {
    await tester.pump(const Duration(milliseconds: 16));

    final feet = game.player.groundFeetY;
    final ahead = game.children
        .whereType<ObstacleComponent>()
        .where((o) => o.baseY < feet + 5) // que todavía no pasó
        .toList()
      ..sort((a, b) => b.baseY.compareTo(a.baseY)); // más cercano primero
    if (ahead.isNotEmpty) {
      game.player.lane = ahead.first.lane.round();
    }
  }
}

/// Planta un zombi en la fila y el carril del jugador: en el próximo frame
/// el motor detecta el choque (camino de colisión determinístico).
Future<void> _touchZombie(WidgetTester tester, RunnerGame game) async {
  await tester.pump(const Duration(milliseconds: 16));
  final zombie = game.spawnZombie(kind: ZombieKind.normal);
  zombie.lane = game.player.lanePos;
  zombie.baseY = game.player.groundFeetY;
  zombie.syncGeometry();
  await tester.pump(const Duration(milliseconds: 16));
}

/// Vibración del teléfono: interruptor de Ajustes (con su guardado) y el
/// disparo en cada choque contra obstáculo, zombi o camión, y en la muerte.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interruptor de Ajustes', () {
    test('arranca prendida', () {
      expect(GameState().hapticsEnabled.value, isTrue);
    });

    test('setHapticsEnabled avisa a los oyentes y no repite el mismo valor',
        () {
      final state = GameState();
      var notifications = 0;
      state.hapticsEnabled.addListener(() => notifications++);

      state.setHapticsEnabled(false);
      expect(state.hapticsEnabled.value, isFalse);
      expect(notifications, 1);

      state.setHapticsEnabled(false); // igual que antes: nadie se entera
      expect(notifications, 1);
    });

    test('la vibración elegida se guarda y se recupera', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore();

      final first = GameState(store: store)..setHapticsEnabled(false);
      expect(first.toJson()['haptics'], isFalse);
      await pumpEventQueue();

      final second = GameState(store: store);
      await second.loadSettings();
      expect(second.hapticsEnabled.value, isFalse);
    });

    test('un guardado viejo sin la clave deja la vibración prendida', () async {
      SharedPreferences.setMockInitialValues({
        'game_save_v1': '{"tutorialSeen":true,"music":false}',
      });

      final state = GameState(store: SettingsStore());
      await state.loadSettings();

      expect(state.hapticsEnabled.value, isTrue);
      // El resto del save sí se carga: la clave nueva es opcional.
      expect(state.tutorialSeen.value, isTrue);
      expect(state.musicEnabled.value, isFalse);
    });

    test('restablecer de fábrica vuelve a prender la vibración', () {
      final state = GameState()..setHapticsEnabled(false);
      state.resetToFactory();
      expect(state.hapticsEnabled.value, isTrue);
    });
  });

  group('vibración en los choques', () {
    testWidgets('chocar contra un obstáculo vibra (hit) y sigue la partida',
        (tester) async {
      final state = GameState()..lives.value = 2;
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        hordeEnabled: false,
        zombiesEnabled: false,
        trucksEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));

      await _driveIntoObstacle(tester, game, () => haptics.cues.isNotEmpty);

      expect(haptics.cues, [HapticCue.hit],
          reason: 'un choque con vidas restantes vibra corto');
      expect(state.lives.value, 1, reason: 'costó una vida');
      expect(state.isGameOver.value, isFalse);
    });

    testWidgets('con una sola vida el choque vibra largo (death)',
        (tester) async {
      final state = GameState()..lives.value = 1;
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        hordeEnabled: false,
        zombiesEnabled: false,
        trucksEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));

      await _driveIntoObstacle(tester, game, () => state.isGameOver.value);

      expect(haptics.cues, [HapticCue.death],
          reason: 'la última vida cierra con la vibración más larga');
      expect(state.lives.value, 0);
    });

    testWidgets('el escudo absorbe y vibra distinto (shield)', (tester) async {
      final state = GameState()..lives.value = 2;
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        hordeEnabled: false,
        zombiesEnabled: false,
        trucksEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));
      game.powerUps.apply(PowerUpKind.shield);

      await _driveIntoObstacle(tester, game, () => haptics.cues.isNotEmpty);

      expect(haptics.cues, [HapticCue.shield],
          reason: 'el escudo avisa con un toque más seco');
      expect(state.lives.value, 2, reason: 'el golpe no cuesta vida');
      expect(game.powerUps.hasShield, isFalse, reason: 'se gastó la carga');
    });

    testWidgets('tocar un zombi vibra como cualquier obstáculo',
        (tester) async {
      final state = GameState()..lives.value = 2;
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        hordeEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));

      await _touchZombie(tester, game);

      expect(haptics.cues, [HapticCue.hit]);
      expect(state.lives.value, 1);
      expect(state.isGameOver.value, isFalse);
    });

    testWidgets('con una sola vida el zombi vibra largo (death)',
        (tester) async {
      final state = GameState()..lives.value = 1;
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        hordeEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));

      await _touchZombie(tester, game);

      expect(haptics.cues, [HapticCue.death]);
      expect(state.isGameOver.value, isTrue);
    });

    testWidgets('con invulnerabilidad activa el cruce no vibra',
        (tester) async {
      final state = GameState()..lives.value = 2;
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        hordeEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));
      game.powerUps.grantInvulnerability(); // respiro recién cobrado

      await _touchZombie(tester, game);

      expect(haptics.cues, isEmpty, reason: 'el choque no cuenta');
      expect(state.lives.value, 2);
    });

    testWidgets('con la vibración apagada en Ajustes no vibra', (tester) async {
      final state = GameState()
        ..lives.value = 2
        ..setHapticsEnabled(false);
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        hordeEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));

      await _touchZombie(tester, game);

      expect(haptics.cues, isEmpty, reason: 'el interruptor corta al instante');
      expect(state.lives.value, 1,
          reason: 'el choque pasó igual: solo falta el feedback táctil');
    });

    testWidgets('la horda que lo alcanza vibra largo (death)', (tester) async {
      final state = GameState();
      final haptics = _FakeHaptics();
      final game = RunnerGame(
        gameState: state,
        haptics: haptics,
        zombiesEnabled: false,
        trucksEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));

      // Tropiezos seguidos: la horda queda encima y lo atrapa.
      for (var i = 0; i < 4; i++) {
        game.horde.stumble();
      }
      await tester.pump(const Duration(milliseconds: 16));

      expect(state.isGameOver.value, isTrue);
      expect(haptics.cues, [HapticCue.death]);
    });
  });

  group('sin plugin de vibración (tests)', () {
    test('GameHaptics no se queja cuando no hay vibrator', () async {
      final haptics = GameHaptics();
      // En el entorno de tests la clase queda muda: si en algún momento
      // volviera a tocar el plugin, estos llamados romperían el test.
      await haptics.play(HapticCue.hit);
      await haptics.play(HapticCue.shield);
      await haptics.play(HapticCue.death);
    });

    test('los cues tienen duraciones distintas para poder diferenciarlos', () {
      expect(
        GameHaptics.shieldDuration,
        lessThan(GameHaptics.hitDuration),
        reason: 'el escudo es el toque más seco',
      );
      expect(
        GameHaptics.hitDuration,
        lessThan(GameHaptics.deathDuration),
        reason: 'la muerte es la más larga',
      );
    });
  });
}
