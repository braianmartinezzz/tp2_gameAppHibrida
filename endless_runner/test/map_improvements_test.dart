import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/coin_component.dart';
import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/player_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';

const _p = Perspective(width: 480, height: 760);

PlayerComponent _player({int lane = 0}) {
  final player = PlayerComponent(
    startPosition: Vector2(_p.width * 0.5, _p.height * 0.86),
    perspective: _p,
  );
  player.lane = lane;
  // laneSpeed = 9 carriles/s: 0.5 s alcanza de sobra para llegar al carril.
  for (var i = 0; i < 60; i++) {
    player.update(1 / 120);
  }
  return player;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ruta con márgenes laterales', () {
    test('el corredor ya no llega pegado al borde de la pantalla', () {
      expect(_p.baseLeftX, greaterThanOrEqualTo(_p.width * 0.10));
      expect(_p.baseRightX, lessThanOrEqualTo(_p.width * 0.90));
    });
  });

  group('colisión barrida (frames largos)', () {
    test('un actor que cruza la fila del jugador en un solo frame choca', () {
      final player = _player();
      final feet = player.groundFeetY;
      final obstacle = ObstacleComponent(
        lane: 0,
        speed: 3000, // ~140 px en un frame de 50 ms
        perspective: _p,
        kind: ObstacleKind.block,
      )
        ..baseY = feet - 100
        ..syncGeometry();

      obstacle.update(0.05);

      // Terminó más de depthMargin *por debajo* de los pies: sin barrido la
      // fila de este frame ya no lo veía.
      expect(obstacle.baseY, greaterThan(feet + 14));
      expect(obstacle.collidesWith(player), isTrue);
    });

    test('mover baseY a mano invalida el tramo barrido', () {
      final player = _player();
      final feet = player.groundFeetY;
      final obstacle = ObstacleComponent(
        lane: 0,
        speed: 3000,
        perspective: _p,
        kind: ObstacleKind.block,
      )
        ..baseY = feet - 100
        ..syncGeometry();
      obstacle.update(0.05);

      obstacle.baseY = feet + 200; // teletransportado lejos de la fila
      obstacle.syncGeometry();
      expect(obstacle.collidesWith(player), isFalse);
    });
  });

  group('monedas: holgura lateral', () {
    CoinComponent coinAt(PlayerComponent player, double gapPx) {
      final coin = CoinComponent(
        lane: 0,
        perspective: _p,
        speed: 0,
        spawnT: 0.13,
      )
        ..baseY = player.groundFeetY
        ..syncGeometry();
      // Deja `gapPx` de aire entre el borde derecho del jugador y la moneda.
      final targetCenter = player.hitBox.right + gapPx + coin.size.x / 2;
      coin.lane = (targetCenter - _p.vanishX) / _p.halfWidthAtT(coin.t);
      coin.syncGeometry();
      return coin;
    }

    test('se recoge aunque falten unos píxeles de solape', () {
      final player = _player();
      expect(coinAt(player, 3).collidesWith(player), isTrue);
    });

    test('pero no se recoge desde otro carril', () {
      final player = _player();
      expect(coinAt(player, 60).collidesWith(player), isFalse);
    });
  });

  group('auto de dos carriles', () {
    ObstacleComponent car(double lane, PlayerComponent player) {
      final c = ObstacleComponent(
        lane: lane,
        speed: 0,
        perspective: _p,
        kind: ObstacleKind.car,
      )
        ..baseY = player.groundFeetY
        ..syncGeometry();
      return c;
    }

    test('cubre exactamente dos carriles', () {
      final player = _player();
      expect(car(0.5, player).coveredLanes, [0.0, 1.0]);
      expect(car(-0.5, player).coveredLanes, [-1.0, 0.0]);
      final span = car(0.5, player).laneHalfSpan;
      expect(span, inInclusiveRange(0.6, 0.75));
    });

    test('choca en sus dos carriles y deja libre el tercero', () {
      expect(car(0.5, _player(lane: 0)).collidesWith(_player(lane: 0)), isTrue);
      expect(car(0.5, _player(lane: 1)).collidesWith(_player(lane: 1)), isTrue);
      expect(car(0.5, _player(lane: -1)).collidesWith(_player(lane: -1)),
          isFalse);
      expect(car(-0.5, _player(lane: 1)).collidesWith(_player(lane: 1)),
          isFalse);
    });

    test('no se salta (hay que cambiar de carril)', () {
      final player = _player(lane: 0)..jump();
      for (var i = 0; i < 36; i++) {
        player.update(1 / 120); // ~0.30 s: techo del salto
      }
      expect(car(0.5, player).collidesWith(player), isTrue);
    });

    testWidgets('en partida nunca arma una pared de tres carriles',
        (tester) async {
      final game = RunnerGame(
        gameState: GameState()..lives.value = 99,
        hordeEnabled: false,
        zombiesEnabled: false, trucksEnabled: false,
      );
      await tester.pumpWidget(GameWidget(game: game));

      var carsSeen = 0;
      for (var i = 0; i < 5000; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        final obstacles = game.children.whereType<ObstacleComponent>().toList();
        for (final c
            in obstacles.where((o) => o.kind == ObstacleKind.car)) {
          carsSeen++;
          expect(c.lane.abs(), 0.5);
          final blocked = <double>{
            for (final o in obstacles)
              if ((o.baseY - c.baseY).abs() < 300) ...o.coveredLanes,
          };
          expect(blocked.length, lessThan(3),
              reason: 'siempre queda un carril libre junto al auto');
        }
      }
      expect(carsSeen, greaterThan(0), reason: 'los autos llegan a aparecer');
    });
  });
}
