import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/player_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/game/zombie_obstacle.dart';
import 'package:runner_flutter/state/game_state.dart';

/// Geometría fija de las pruebas unitarias (480x760, como el preview).
const _p = Perspective(width: 480, height: 760);

PlayerComponent _player() => PlayerComponent(
      startPosition: Vector2(_p.width * 0.5, _p.height * 0.86),
      perspective: _p,
    );

/// Jugador con [seconds] de salto en las piernas (0.30 s ≈ techo, ~60 px).
PlayerComponent _jumping({double seconds = 0.15}) {
  final player = _player();
  player.jump();
  const step = 1 / 120;
  for (var t = 0.0; t < seconds; t += step) {
    player.update(step);
  }
  return player;
}

ZombieObstacle _zombie(
  ZombieKind kind, {
  double lane = 0,
  double difficulty = 0,
  double speed = 0,
  double? phase,
}) =>
    ZombieObstacle(
      lane: lane,
      speed: speed,
      perspective: _p,
      kind: kind,
      difficulty: difficulty,
      phase: phase,
      random: Random(7),
    );

/// Zombi en la fila del jugador (patrulla centrada y a mitad de tramo: queda
/// en el carril 0).
ZombieObstacle _atRow(
  PlayerComponent player,
  ZombieKind kind, {
  double lane = 0,
  double difficulty = 0,
}) {
  final zombie = _zombie(kind, lane: lane, difficulty: difficulty, phase: 0.5);
  zombie.baseY = player.groundFeetY;
  zombie.syncGeometry();
  return zombie;
}

/// Avanza [zombie] [seconds] en pasos de 1/60 s.
void _run(ZombieObstacle zombie, double seconds) {
  const step = 1 / 60;
  for (var t = 0.0; t < seconds; t += step) {
    zombie.update(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZombieKind: los tres tipos se distinguen', () {
    test('lento > normal > rápido en tamaño; al revés en velocidad', () {
      expect(ZombieKind.slow.width, greaterThan(ZombieKind.normal.width));
      expect(ZombieKind.normal.width, greaterThan(ZombieKind.fast.width));
      expect(ZombieKind.slow.height, greaterThan(ZombieKind.normal.height));
      expect(ZombieKind.normal.height, greaterThan(ZombieKind.fast.height));

      expect(
        ZombieKind.slow.lateralSpeed,
        lessThan(ZombieKind.normal.lateralSpeed),
      );
      expect(
        ZombieKind.normal.lateralSpeed,
        lessThan(ZombieKind.fast.lateralSpeed),
      );
    });

    test('cada tipo tiene su propio color de piel, ropa y aro', () {
      expect(ZombieKind.values.map((k) => k.skin).toSet(), hasLength(3));
      expect(ZombieKind.values.map((k) => k.clothes).toSet(), hasLength(3));
      expect(ZombieKind.values.map((k) => k.ring).toSet(), hasLength(3));
    });

    test('lento y normal patrullan; el rápido persigue', () {
      expect(ZombieKind.slow.behavior, ZombieBehavior.patrol);
      expect(ZombieKind.normal.behavior, ZombieBehavior.patrol);
      expect(ZombieKind.fast.behavior, ZombieBehavior.chase);
    });

    test('roll: sin rápidos antes de fastUnlock', () {
      for (var i = 0; i < 100; i++) {
        expect(
          ZombieKind.roll(ZombieKind.fastUnlock - 0.01, i / 100),
          isNot(ZombieKind.fast),
        );
      }
      expect(ZombieKind.roll(0, 0.3), ZombieKind.slow);
      expect(ZombieKind.roll(0, 0.9), ZombieKind.normal);
    });

    test('roll: con dificultad máxima salen los tres, y más rápidos', () {
      expect(ZombieKind.roll(1, 0.0), ZombieKind.fast);
      expect(ZombieKind.roll(1, 0.6), ZombieKind.slow);
      expect(ZombieKind.roll(1, 0.95), ZombieKind.normal);

      int fastCount(double difficulty) => [
            for (var i = 0; i < 1000; i++) i / 1000
          ].where((r) => ZombieKind.roll(difficulty, r) == ZombieKind.fast).length;
      expect(fastCount(1.0), greaterThan(fastCount(0.4)));
    });
  });

  group('ZombieObstacle: dificultad', () {
    test('la dificultad acelera y agranda al zombi', () {
      final easy = _zombie(ZombieKind.normal, difficulty: 0);
      final hard = _zombie(ZombieKind.normal, difficulty: 1);

      expect(easy.lateralSpeed, ZombieKind.normal.lateralSpeed);
      expect(
        hard.lateralSpeed,
        closeTo(
          ZombieKind.normal.lateralSpeed * (1 + ZombieObstacle.speedGain),
          1e-9,
        ),
      );

      final player = _player();
      final a = _atRow(player, ZombieKind.normal, difficulty: 0);
      final b = _atRow(player, ZombieKind.normal, difficulty: 1);
      expect(b.size.x, greaterThan(a.size.x));
      expect(b.size.y, greaterThan(a.size.y));
    });

    test('la dificultad se acota a 0..1', () {
      final zombie = _zombie(ZombieKind.fast, difficulty: 5);
      expect(
        zombie.lateralSpeed,
        closeTo(ZombieKind.fast.lateralSpeed * (1 + ZombieObstacle.speedGain),
            1e-9),
      );
      expect(zombie.sizeFactor, closeTo(1 + ZombieObstacle.sizeGain, 1e-9));
    });
  });

  group('ZombieObstacle: patrulla', () {
    test('el tramo depende del tipo y no sale del corredor', () {
      final left = _zombie(ZombieKind.slow, lane: -0.5);
      expect(left.patrolMin, closeTo(-1, 1e-9));
      expect(left.patrolMax, closeTo(0, 1e-9));

      final right = _zombie(ZombieKind.slow, lane: 0.5);
      expect(right.patrolMin, closeTo(0, 1e-9));
      expect(right.patrolMax, closeTo(1, 1e-9));

      final wide = _zombie(ZombieKind.normal);
      expect(wide.patrolMin, closeTo(-1, 1e-9));
      expect(wide.patrolMax, closeTo(1, 1e-9));
    });

    for (final kind in [ZombieKind.slow, ZombieKind.normal]) {
      test('${kind.name}: va y vuelve entre los extremos sin pasarse', () {
        final zombie = _zombie(kind, lane: kind == ZombieKind.slow ? -0.5 : 0);
        var lo = double.infinity;
        var hi = -double.infinity;
        var flips = 0;
        var lastDir = zombie.direction;

        const step = 1 / 60;
        for (var t = 0.0; t < 20; t += step) {
          zombie.update(step);
          lo = min(lo, zombie.lane);
          hi = max(hi, zombie.lane);
          if (zombie.direction != lastDir) {
            flips++;
            lastDir = zombie.direction;
          }
          expect(zombie.lane, inInclusiveRange(zombie.patrolMin, zombie.patrolMax));
        }

        expect(lo, closeTo(zombie.patrolMin, 1e-9));
        expect(hi, closeTo(zombie.patrolMax, 1e-9));
        expect(flips, greaterThanOrEqualTo(2), reason: 'ida y vuelta');
      });
    }

    test('el lento recorre menos que el normal en el mismo tiempo', () {
      final slow = _zombie(ZombieKind.slow, lane: -0.5, phase: 0);
      final normal = _zombie(ZombieKind.normal, phase: 0);
      final slowStart = slow.lane;
      final normalStart = normal.lane;
      // La patrulla arranca hacia un lado cualquiera: se mide la distancia
      // total recorrida en 1 s sin llegar a los extremos.
      var slowPath = 0.0;
      var normalPath = 0.0;
      var slowLast = slowStart;
      var normalLast = normalStart;
      const step = 1 / 60;
      for (var t = 0.0; t < 0.8; t += step) {
        slow.update(step);
        normal.update(step);
        slowPath += (slow.lane - slowLast).abs();
        normalPath += (normal.lane - normalLast).abs();
        slowLast = slow.lane;
        normalLast = normal.lane;
      }
      expect(normalPath, greaterThan(slowPath));
    });

    test('baja por el corredor a la velocidad del piso', () {
      final zombie = _zombie(ZombieKind.normal, speed: 300);
      final before = zombie.baseY;
      _run(zombie, 0.5);
      expect(zombie.baseY, greaterThan(before));
    });
  });

  group('ZombieObstacle: persecución', () {
    test('sigue al jugador antes de lockT y después fija su carril', () {
      final zombie = _zombie(ZombieKind.fast, lane: 1)..targetLane = -1;
      expect(zombie.t, lessThan(ZombieObstacle.lockT));

      _run(zombie, 3);
      expect(zombie.lane, closeTo(-1, 1e-9), reason: 'llegó al carril del jugador');
      expect(zombie.locked, isFalse);

      // Cruza la profundidad de compromiso.
      zombie.baseY = _p.yAtT(ZombieObstacle.lockT + 0.05);
      _run(zombie, 0.1);
      expect(zombie.locked, isTrue);

      // El jugador se cambia de carril: ya no lo sigue.
      zombie.targetLane = 1;
      _run(zombie, 1);
      expect(zombie.lane, closeTo(-1, 1e-9));
    });

    test('el persecutor no se pasa del carril objetivo', () {
      final zombie = _zombie(ZombieKind.fast, lane: 1)..targetLane = 0;
      var minLane = double.infinity;
      const step = 1 / 60;
      for (var t = 0.0; t < 2; t += step) {
        zombie.update(step);
        minLane = min(minLane, zombie.lane);
      }
      expect(minLane, greaterThanOrEqualTo(-1e-9));
      expect(zombie.lane, closeTo(0, 1e-9));
    });

    test('tras comprometerse queda tiempo de sobra para esquivar', () {
      final player = _player();
      // Distancia en pantalla entre la profundidad de compromiso y el
      // jugador, recorrida a 620 px/s (la velocidad máxima que contempla el
      // diseño de los obstáculos).
      final px = player.groundFeetY - _p.yAtT(ZombieObstacle.lockT);
      final reaction = px / 620;
      final laneChange = 1 / PlayerComponent.laneSpeed;
      expect(reaction, greaterThan(2 * laneChange));
    });
  });

  group('ZombieObstacle: colisión', () {
    for (final kind in ZombieKind.values) {
      test('${kind.name}: choca en el mismo carril y no en otro', () {
        final player = _player();
        expect(_atRow(player, kind).collidesWith(player), isTrue);

        // En el carril de la derecha (el jugador está en el central): no.
        final side = _zombie(kind, lane: 1, phase: 1.0);
        side.baseY = player.groundFeetY;
        side.syncGeometry();
        expect(side.lane, closeTo(1, 1e-9));
        expect(side.collidesWith(player), isFalse);

        final far = _atRow(player, kind)..baseY = player.groundFeetY - 200;
        far.syncGeometry();
        expect(far.collidesWith(player), isFalse);
      });

      test('${kind.name}: no se salta ni se pasa agachado', () {
        final peak = _jumping(seconds: 0.30);
        expect(peak.jumpY, greaterThan(50), reason: 'cerca del techo del salto');
        expect(_atRow(peak, kind).collidesWith(peak), isTrue);

        final rolling = _player()..roll();
        expect(_atRow(rolling, kind).collidesWith(rolling), isTrue);
      });
    }
  });

  group('ZombieObstacle: dibujo', () {
    testWidgets('cada tipo dibuja y el lento ocupa más que el normal y el rápido',
        (tester) async {
      final player = _player();
      final counts = <ZombieKind, int>{};

      await tester.runAsync(() async {
        for (final kind in ZombieKind.values) {
          final zombie = _atRow(player, kind);
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.translate(40, 70);
          zombie.render(canvas);
          final image = await recorder.endRecording().toImage(160, 200);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          final data = bytes!.buffer.asUint8List();
          counts[kind] = _opaquePixels(data);
        }
      });

      for (final kind in ZombieKind.values) {
        expect(counts[kind], greaterThan(200), reason: '${kind.name} se dibuja');
      }
      expect(counts[ZombieKind.slow]!, greaterThan(counts[ZombieKind.normal]!));
      expect(counts[ZombieKind.normal]!, greaterThan(counts[ZombieKind.fast]!));
    });

    test('recién nacido (alpha 0) no dibuja nada y no falla', () {
      final zombie = _zombie(ZombieKind.fast); // nace en spawnT: alpha 0
      expect(zombie.alpha, 0);
      zombie.render(Canvas(ui.PictureRecorder()));
    });
  });

  group('RunnerGame con zombis', () {
    testWidgets('aparecen solos pasado el primer tramo de la partida',
        (tester) async {
      final gameState = GameState()..lives.value = 1000000;
      final game = RunnerGame(gameState: gameState, hordeEnabled: false);
      await tester.pumpWidget(GameWidget(game: game));

      var sawZombie = false;
      for (var i = 0; i < 900 && !sawZombie; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (i < 400) {
          expect(game.zombies, isEmpty, reason: 'no hay zombis en los primeros ~6 s');
        }
        sawZombie = game.zombies.isNotEmpty;
      }
      expect(sawZombie, isTrue);
    });

    testWidgets('un zombi nunca llega pegado a un obstáculo fijo',
        (tester) async {
      final gameState = GameState()..lives.value = 1000000;
      final game = RunnerGame(gameState: gameState, hordeEnabled: false);
      await tester.pumpWidget(GameWidget(game: game));

      var sawZombie = false;
      for (var i = 0; i < 3000; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        for (final zombie in game.zombies) {
          sawZombie = true;
          for (final obstacle in game.children.whereType<ObstacleComponent>()) {
            expect((obstacle.baseY - zombie.baseY).abs(), greaterThan(60));
          }
        }
      }
      expect(sawZombie, isTrue);
      expect(gameState.isGameOver.value, isFalse);
    });

    testWidgets('tocar un zombi cuesta una vida y no corta la partida',
        (tester) async {
      final state = GameState();
      expect(state.lives.value, GameState.maxLives);
      final game = RunnerGame(gameState: state, hordeEnabled: false);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));

      final zombie = game.spawnZombie(kind: ZombieKind.normal);
      zombie.lane = game.player.lanePos;
      zombie.baseY = game.player.groundFeetY;
      zombie.syncGeometry();
      await tester.pump(const Duration(milliseconds: 16));

      expect(state.lives.value, GameState.maxLives - 1);
      expect(state.isGameOver.value, isFalse);
      expect(game.powerUps.isInvulnerable, isTrue, reason: 'queda un respiro');
    });

    testWidgets('con una sola vida, el zombi mata', (tester) async {
      final state = GameState()..lives.value = 1;
      final game = RunnerGame(gameState: state, hordeEnabled: false);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));

      final zombie = game.spawnZombie(kind: ZombieKind.normal);
      zombie.lane = game.player.lanePos;
      zombie.baseY = game.player.groundFeetY;
      zombie.syncGeometry();
      await tester.pump(const Duration(milliseconds: 16));

      expect(state.isGameOver.value, isTrue);
    });

    testWidgets('reiniciar limpia los zombis y vuelve a esperar el primero',
        (tester) async {
      final game = RunnerGame(
        gameState: GameState(),
        hordeEnabled: false,
        zombiesEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));

      game.spawnZombie(kind: ZombieKind.slow);
      game.spawnZombie(kind: ZombieKind.fast);
      expect(game.zombies, hasLength(2));

      game.restartRun();
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.zombies, isEmpty);
    });
  });
}

/// Píxeles con alfa > 0 en un buffer RGBA.
int _opaquePixels(Uint8List rgba) {
  var n = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 0) n++;
  }
  return n;
}
