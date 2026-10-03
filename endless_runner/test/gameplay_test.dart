import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/player_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';

/// Geometría fija de las pruebas unitarias (480x760, como el preview).
const _p = Perspective(width: 480, height: 760);

PlayerComponent _player() => PlayerComponent(
      startPosition: Vector2(_p.width * 0.5, _p.height * 0.86),
      perspective: _p,
    );

/// Obstáculo del carril central exactamente en la fila del jugador.
ObstacleComponent _atRow(PlayerComponent player, ObstacleKind kind) {
  final obstacle = ObstacleComponent(
    lane: 0,
    speed: 0,
    perspective: _p,
    kind: kind,
  );
  obstacle.baseY = player.groundFeetY;
  obstacle.syncGeometry();
  return obstacle;
}

/// Jugador con [seconds] de salto en las piernas (0.15 s ≈ 43 px de altura,
/// 0.30 s ≈ techo del salto ~60 px).
PlayerComponent _jumping({double seconds = 0.15}) {
  final player = _player();
  player.jump();
  const step = 1 / 120;
  for (var t = 0.0; t < seconds; t += step) {
    player.update(step);
  }
  return player;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Colisión por altura: banda del obstáculo vs altura del jugador.
  // -------------------------------------------------------------------------
  group('colisión por altura', () {
    test('valla: choca parado y se salta saltando', () {
      final standing = _player();
      expect(
        _atRow(standing, ObstacleKind.lowBarrier).collidesWith(standing),
        isTrue,
        reason: 'parado la valla le pega en las piernas',
      );

      final jumping = _jumping();
      expect(jumping.jumpY, greaterThan(20));
      expect(
        _atRow(jumping, ObstacleKind.lowBarrier).collidesWith(jumping),
        isFalse,
        reason: 'con los pies arriba de la valla pasa',
      );
    });

    test('túnel: choca parado, pasa agachado y no se salta', () {
      final standing = _player();
      expect(
        _atRow(standing, ObstacleKind.overhead).collidesWith(standing),
        isTrue,
      );

      final rolling = _player()..roll();
      expect(rolling.isRolling, isTrue);
      expect(
        _atRow(rolling, ObstacleKind.overhead).collidesWith(rolling),
        isFalse,
        reason: 'agachado (16 px) entra por debajo de la losa',
      );

      final jumping = _jumping();
      expect(
        _atRow(jumping, ObstacleKind.overhead).collidesWith(jumping),
        isTrue,
        reason: 'la losa llega hasta arriba: saltar no sirve',
      );
    });

    test('bloque: no se salta ni se pasa agachado (hay que cambiar de carril)',
        () {
      final standing = _player();
      expect(
        _atRow(standing, ObstacleKind.block).collidesWith(standing),
        isTrue,
      );

      final rolling = _player()..roll();
      expect(
        _atRow(rolling, ObstacleKind.block).collidesWith(rolling),
        isTrue,
      );

      final jumping = _jumping(seconds: 0.3); // techo del salto (~60 px)
      expect(jumping.jumpY, greaterThan(50));
      expect(
        _atRow(jumping, ObstacleKind.block).collidesWith(jumping),
        isTrue,
        reason: 'el contenedor es más alto que el techo del salto',
      );
    });

    test('sin solape de carril no hay colisión', () {
      final player = _player(); // carril 0

      final side = ObstacleComponent(
        lane: 1,
        speed: 0,
        perspective: _p,
        kind: ObstacleKind.block,
      );
      side.baseY = player.groundFeetY;
      side.syncGeometry();
      expect(side.collidesWith(player), isFalse);

      expect(
        _atRow(player, ObstacleKind.block).collidesWith(player),
        isTrue,
        reason: 'en su propio carril sí',
      );
    });

    test('fuera de la fila no hay colisión aunque compartan carril', () {
      final player = _player();
      final obstacle = ObstacleComponent(
        lane: 0,
        speed: 0,
        perspective: _p,
        kind: ObstacleKind.block,
      );

      // Todavía viene desde lejos: su caja en pantalla "invade" la del
      // jugador, pero la fila decide (regresión del golpe fantasma).
      obstacle.baseY = player.groundFeetY - 60;
      obstacle.syncGeometry();
      expect(obstacle.collidesWith(player), isFalse);

      obstacle.baseY = player.groundFeetY;
      obstacle.syncGeometry();
      expect(obstacle.collidesWith(player), isTrue);

      // Ya pasó por delante: tampoco pega.
      obstacle.baseY = player.groundFeetY + 60;
      obstacle.syncGeometry();
      expect(obstacle.collidesWith(player), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // Movimiento por carriles.
  // -------------------------------------------------------------------------
  group('carriles', () {
    test('se anima hasta el objetivo y no se pasa de los bordes', () {
      final player = _player();
      final t = _p.tAtY(player.groundY);
      expect(player.position.x, closeTo(_p.xAtT(0, t), 1e-3));

      player.moveLane(1);
      expect(player.lane, 1);
      player.update(1 / 60);
      expect(
        player.position.x,
        lessThan(_p.xAtT(1, t)),
        reason: 'va camino del carril, no teletransporta',
      );

      for (var i = 0; i < 30; i++) {
        player.update(1 / 60);
      }
      expect(player.lanePos, 1);
      expect(player.position.x, closeTo(_p.xAtT(1, t), 1e-3));

      for (var i = 0; i < 5; i++) {
        player.moveLane(1);
      }
      expect(player.lane, 1, reason: 'no se pasa del borde derecho');

      for (var i = 0; i < 5; i++) {
        player.moveLane(-1);
      }
      expect(player.lane, -1);
      for (var i = 0; i < 60; i++) {
        player.update(1 / 60);
      }
      expect(player.position.x, closeTo(_p.xAtT(-1, t), 1e-3));
    });

    test('la X del carril no cambia al saltar', () {
      final player = _player();
      final before = player.position.x;
      player.jump();
      for (var i = 0; i < 30; i++) {
        player.update(1 / 60);
      }
      expect(player.position.x, before);
      expect(player.position.y, lessThan(player.groundY), reason: 'está arriba');
    });
  });

  // -------------------------------------------------------------------------
  // Salto y agachado.
  // -------------------------------------------------------------------------
  group('salto y agachado', () {
    test('la parábola sube, toca el techo y aterriza', () {
      final player = _player();
      expect(player.jump(), isTrue);
      expect(player.isAirborne, isTrue);
      expect(player.jump(), isFalse, reason: 'no salta dos veces');

      var maxY = 0.0;
      for (var i = 0; i < 90 && player.isAirborne; i++) {
        player.update(1 / 60);
        maxY = max(maxY, player.jumpY);
      }

      expect(player.isAirborne, isFalse);
      expect(player.jumpY, 0);
      expect(player.jumpV, 0);
      expect(maxY, inInclusiveRange(50, 70), reason: 'techo ~60 px');
      expect(player.position.y, closeTo(player.groundY, 1e-9));
    });

    test('agachado achica la caja y no deja saltar', () {
      final standing = _player();
      expect(standing.hitBox.height, PlayerComponent.playerSize);
      expect(standing.bodyHeight, PlayerComponent.playerSize);

      final rolling = _player()..roll();
      expect(rolling.isRolling, isTrue);
      expect(rolling.hitBox.height, PlayerComponent.rollHeight);
      expect(rolling.bodyHeight, PlayerComponent.rollHeight);
      expect(rolling.jump(), isFalse, reason: 'agachado no salta');
    });

    test('tirarse desde el aire cae rápido y rueda al aterrizar', () {
      final player = _player();
      player.jump();
      player.update(1 / 60);
      expect(player.roll(), isTrue);
      expect(player.isRolling, isFalse, reason: 'todavía está en el aire');

      for (var i = 0; i < 120 && !player.isRolling; i++) {
        player.update(1 / 60);
      }
      expect(player.isRolling, isTrue, reason: 'rueda apenas toca el suelo');
      expect(player.isAirborne, isFalse);
      expect(player.hitBox.height, PlayerComponent.rollHeight);
    });
  });

  // -------------------------------------------------------------------------
  // Gestos de entrada (solo swipe, sin botones externos).
  // -------------------------------------------------------------------------
  testWidgets('los gestos de swipe controlan al jugador', (tester) async {
    final gameState = GameState();
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump(const Duration(milliseconds: 50));

    expect(game.player.lane, 0);

    await tester.drag(find.byType(GameWidget<RunnerGame>), const Offset(90, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.player.lane, 1, reason: 'swipe a la derecha → carril +1');

    await tester.drag(find.byType(GameWidget<RunnerGame>), const Offset(-90, 0));
    await tester.pump(const Duration(milliseconds: 50));
    expect(game.player.lane, 0, reason: 'swipe a la izquierda → carril -1');

    await tester.drag(find.byType(GameWidget<RunnerGame>), const Offset(0, -90));
    await tester.pump(const Duration(milliseconds: 30));
    expect(game.player.isAirborne, isTrue, reason: 'swipe hacia arriba → salta');
    expect(game.player.isRolling, isFalse);

    // En el aire, el swipe hacia abajo lo tira y rueda al aterrizar.
    await tester.drag(find.byType(GameWidget<RunnerGame>), const Offset(0, 90));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(game.player.isAirborne, isFalse);
    expect(game.player.isRolling, isTrue, reason: 'swipe abajo → rueda');
  });

  // -------------------------------------------------------------------------
  // El spawn nunca cierra los tres carriles.
  // -------------------------------------------------------------------------
  testWidgets('el spawn deja siempre un carril libre para esquivar',
      (tester) async {
    final gameState = GameState()
      ..diamonds.value = 1000000; // invulnerable: el test mide el spawn
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));

    for (var i = 0; i < 3000; i++) {
      await tester.pump(const Duration(milliseconds: 16));

      final feet = game.player.groundFeetY;
      final ahead = game.children
          .whereType<ObstacleComponent>()
          .where((o) => o.baseY < feet + 40) // aún no pasaron al jugador
          .toList()
        ..sort((a, b) => b.baseY.compareTo(a.baseY)); // más cercano primero

      // 1) Ninguna tanda de tres consecutivos cubre los tres carriles.
      for (var k = 0; k + 2 < ahead.length; k++) {
        final lanes = {ahead[k].lane, ahead[k + 1].lane, ahead[k + 2].lane};
        expect(
          lanes.length,
          lessThan(3),
          reason: 'la tanda $k cierra el corredor (${ahead
              .skip(k)
              .take(3)
              .map((o) => o.lane)
              .join(', ')})',
        );
      }

      // 2) La ventana de reacción nunca acumula más de tres obstáculos.
      expect(
        ahead.where((o) => o.baseY > feet - 170).length,
        lessThanOrEqualTo(3),
        reason: 'se apelotonan en la ventana de reacción',
      );
    }

    expect(
      game.children.whereType<ObstacleComponent>(),
      isNotEmpty,
      reason: 'en ~48 s de juego deberían haber spawneado obstáculos',
    );
    expect(gameState.isGameOver.value, isFalse);
  });

  // -------------------------------------------------------------------------
  // Fin de partida end-to-end: spawn → colisión → game over.
  // -------------------------------------------------------------------------
  testWidgets('chocar sin diamantes termina la partida', (tester) async {
    final gameState = GameState()..diamonds.value = 0;
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));

    // Piloto automático: se planta en el carril del próximo obstáculo.
    for (var i = 0; i < 1000 && !gameState.isGameOver.value; i++) {
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

    expect(
      gameState.isGameOver.value,
      isTrue,
      reason: 'sin diamantes, el primer choque corta la partida',
    );
    expect(gameState.diamonds.value, 0);
    expect(gameState.score.value, greaterThan(0));
  });
}
