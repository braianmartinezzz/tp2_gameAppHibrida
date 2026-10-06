import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/player_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/game/truck_component.dart';
import 'package:runner_flutter/state/game_state.dart';

/// Geometría fija de las pruebas unitarias (480x760, como el preview).
const _p = Perspective(width: 480, height: 760);

TruckComponent _truck({
  double lane = 0,
  double zFront = 2.4,
  double boxLength = 0.55,
  bool ramp = true,
  TruckLook look = TruckLook.white,
}) =>
    TruckComponent(
      lane: lane,
      speed: 0,
      perspective: _p,
      boxLength: boxLength,
      hasRamp: ramp,
      look: look,
      startZ: zFront,
    );

PlayerComponent _player() => PlayerComponent(
      startPosition: Vector2(_p.width * 0.5, _p.height * 0.86),
      perspective: _p,
    );

/// Juego sin zombis, horda ni camiones espontáneos: cada test pone los suyos.
RunnerGame _game(GameState state) => RunnerGame(
      gameState: state,
      hordeEnabled: false,
      zombiesEnabled: false,
      trucksEnabled: false,
    );

Future<void> _frames(WidgetTester tester, int n, [void Function()? each]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    each?.call();
  }
}

int _paintedPixels(Uint8List rgba) {
  var n = 0;
  for (var i = 3; i < rgba.length; i += 4) {
    if (rgba[i] > 0) n++;
  }
  return n;
}

void main() {
  // -------------------------------------------------------------------------
  // Geometría: qué techo hay bajo los pies.
  // -------------------------------------------------------------------------
  group('TruckComponent.surfaceAt', () {
    // zFront 2.4, caja 0.55 u, cabina 0.16 u, rampa 0.20 u:
    //   cabina [1.18, 1.385] · caja [1.385, 2.4] · rampa (2.4, 2.931].
    const halfPlayer = 0.09;

    test('techo de la caja: su altura escalada a la profundidad del jugador', () {
      final t = _truck();
      expect(
        t.surfaceAt(1.8, 0, halfPlayer),
        closeTo(TruckComponent.roofHeight * 0.8, 1e-9),
      );
    });

    test('la cabina es un escalón más bajo que la caja', () {
      final t = _truck();
      final cab = t.surfaceAt(1.3, 0, halfPlayer)!;
      final box = t.surfaceAt(1.5, 0, halfPlayer)!;
      expect(cab, closeTo(TruckComponent.cabHeight * 0.3, 1e-9));
      expect(cab / 0.3, lessThan(box / 0.5));
    });

    test('la rampa sube sin saltos: 0 en el pie, el techo en el borde', () {
      final t = _truck();
      expect(t.surfaceAt(t.zRampStart, 0, halfPlayer), closeTo(0, 1e-9));
      // Apenas del lado de la rampa del frente de la caja.
      final top = t.surfaceAt(t.zFront * 1.0000001, 0, halfPlayer)!;
      expect(top, closeTo(TruckComponent.roofHeight * (t.zFront - 1), 0.01));
      // A mitad de recorrido (en u) vale la mitad.
      final zMid = t.zFront * exp(TruckComponent.rampLength / 2);
      expect(
        t.surfaceAt(zMid, 0, halfPlayer),
        closeTo(TruckComponent.roofHeight * (zMid - 1) / 2, 1e-6),
      );
    });

    test('fuera del tramo del camión no hay superficie', () {
      final t = _truck();
      expect(t.surfaceAt(t.zRampStart * 1.1, 0, halfPlayer), isNull);
      expect(t.surfaceAt(t.zBack * 0.95, 0, halfPlayer), isNull);
    });

    test('sin rampa, delante de la caja no hay nada que pisar', () {
      final t = _truck(ramp: false);
      expect(t.surfaceAt(t.zFront * 1.05, 0, halfPlayer), isNull);
      expect(t.surfaceAt(1.8, 0, halfPlayer), isNotNull);
    });

    test('el carril cuenta: de costado no hay techo', () {
      final t = _truck();
      expect(t.surfaceAt(1.8, 1.0, halfPlayer), isNull);
      expect(t.surfaceAt(1.8, 0.6, halfPlayer), isNull);
      expect(t.surfaceAt(1.8, 0.45, halfPlayer), isNotNull,
          reason: 'la mitad del cuerpo todavía pisa el techo');
    });
  });

  // -------------------------------------------------------------------------
  // El corredor sobre una superficie.
  // -------------------------------------------------------------------------
  group('PlayerComponent sobre un techo', () {
    test('apoyado en una superficie no está en el aire y la acompaña', () {
      final player = _player()..groundHeight = 50;
      player.update(1 / 60);
      expect(player.jumpY, 50);
      expect(player.isAirborne, isFalse);

      player.groundHeight = 70; // la rampa sube
      player.update(1 / 60);
      expect(player.jumpY, 70);
      expect(player.isAirborne, isFalse);
    });

    test('si la superficie se acaba, cae hasta la ruta', () {
      final player = _player()..groundHeight = 50;
      player.update(1 / 60);

      player.groundHeight = 0;
      expect(player.isAirborne, isTrue);
      for (var i = 0; i < 120; i++) {
        player.update(1 / 60);
      }
      expect(player.jumpY, 0);
      expect(player.isAirborne, isFalse);
    });

    test('salta desde el techo y vuelve a caer sobre el techo', () {
      final player = _player()..groundHeight = 50;
      for (var i = 0; i < 5; i++) {
        player.update(1 / 60);
      }
      player.jump();
      var apex = 0.0;
      for (var i = 0; i < 90; i++) {
        player.update(1 / 60);
        apex = max(apex, player.jumpY);
      }
      expect(apex, greaterThan(90), reason: 'salta ~60 px sobre el techo');
      expect(player.jumpY, 50);
      expect(player.isAirborne, isFalse);
    });

    test('el empujón de un choque cambia de carril más rápido', () {
      final normal = _player()..lane = 1;
      final pushed = _player()..bounceTo(1);
      for (var i = 0; i < 3; i++) {
        normal.update(1 / 60);
        pushed.update(1 / 60);
      }
      expect(pushed.lanePos, greaterThan(normal.lanePos));
    });

    test('resetTo suelta la superficie y el empujón', () {
      final player = _player()
        ..groundHeight = 60
        ..bounceTo(-1);
      player.resetTo(startPosition: Vector2(_p.width * 0.5, _p.height * 0.86));
      expect(player.groundHeight, 0);
      expect(player.bounceTimer, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Dibujo.
  // -------------------------------------------------------------------------
  testWidgets('dibuja todos los aspectos, carriles y variantes', (tester) async {
    await tester.runAsync(() async {
      for (final look in TruckLook.values) {
        for (final lane in const [-1.0, 0.0, 1.0]) {
          for (final ramp in const [true, false]) {
            final recorder = ui.PictureRecorder();
            final canvas = ui.Canvas(recorder);
            _truck(lane: lane, zFront: 1.7, ramp: ramp, look: look)
                .render(canvas);
            final image = await recorder.endRecording().toImage(480, 760);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.rawRgba);
            expect(
              _paintedPixels(bytes!.buffer.asUint8List()),
              greaterThan(2000),
              reason: '$look lane=$lane ramp=$ramp',
            );
          }
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  // En el juego.
  // -------------------------------------------------------------------------
  testWidgets('de frente sin rampa: cuesta una vida y rebota al carril vecino',
      (tester) async {
    final state = GameState();
    final game = _game(state);
    await tester.pumpWidget(GameWidget(game: game));
    final lives = state.lives.value;
    expect(game.player.lane, 0);

    final truck = game.spawnTruck(lane: 0, ramp: false, length: 0.4, z: 1.5);
    var hit = false;
    for (var i = 0; i < 150 && !hit; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      hit = state.lives.value < lives;
    }
    expect(hit, isTrue, reason: 'el frente del camión golpea al jugador');
    expect(truck.wasTouching, isTrue);

    await _frames(tester, 30);
    expect(game.player.lane, isNot(0), reason: 'rebota al carril de al lado');
    expect(game.player.lanePos.abs(), greaterThan(0.9));
    expect(state.lives.value, lives - 1, reason: 'un solo golpe por cruce');
    expect(state.isGameOver.value, isFalse);
  });

  testWidgets('por la rampa se sube al techo, se corre arriba y se juntan diamantes',
      (tester) async {
    final state = GameState();
    final game = _game(state);
    await tester.pumpWidget(GameWidget(game: game));
    final diamonds = state.diamonds.value;

    final truck = game.spawnTruck(lane: 0, ramp: true, length: 0.6, z: 1.45);
    expect(truck.pendingCoins, isNotEmpty);

    var maxHeight = 0.0;
    var onRoof = false;
    var bounced = false;
    await _frames(tester, 260, () {
      // Invulnerable a propósito: lo que se mide es que la rampa NO empuje.
      game.powerUps.grantInvulnerability();
      final player = game.player;
      maxHeight = max(maxHeight, player.jumpY);
      if (player.lane != 0) bounced = true;
      if (player.groundHeight > 60 &&
          !player.isAirborne &&
          player.jumpY == player.groundHeight) {
        onRoof = true;
      }
    });

    expect(bounced, isFalse, reason: 'la rampa se sube, no es un muro');
    expect(maxHeight, greaterThan(60), reason: 'llegó a la altura del techo');
    expect(onRoof, isTrue, reason: 'corrió apoyado sobre el techo');
    expect(
      state.diamonds.value,
      greaterThanOrEqualTo(diamonds + 6),
      reason: 'los diamantes del techo (9 gemas, una dorada) se recogen',
    );
  });

  testWidgets('al terminar el camión el corredor cae a la ruta', (tester) async {
    final state = GameState();
    final game = _game(state);
    await tester.pumpWidget(GameWidget(game: game));

    game.spawnTruck(lane: 0, ramp: true, length: 0.4, z: 1.5);
    await _frames(tester, 520, game.powerUps.grantInvulnerability);

    expect(game.trucks, isEmpty, reason: 'el camión ya pasó entero');
    expect(game.player.groundHeight, 0);
    expect(game.player.jumpY, 0);
    expect(game.player.isAirborne, isFalse);
  });

  testWidgets('nada nace dentro de un camión: ni en su carril ni pesado',
      (tester) async {
    final state = GameState();
    final game = _game(state);
    await tester.pumpWidget(GameWidget(game: game));
    // El montaje puede dejar obstáculos recién agregados en la cola de Flame:
    // si se saca la foto ahora no entran en `before` y más tarde aparecen
    // como si hubieran nacido con el camión (cuando en realidad nacieron
    // antes, sin camión). Se dejan pasar unos cuadros para que asienten.
    await _frames(tester, 10);
    final before = game.children.whereType<ObstacleComponent>().toSet();

    game.spawnTruck(lane: 1, ramp: true, length: 0.9); // en el horizonte
    final seen = <ObstacleComponent>{};
    await _frames(tester, 240, () {
      game.powerUps.grantInvulnerability();
      seen.addAll(game.children.whereType<ObstacleComponent>());
    });
    seen.removeAll(before);

    expect(seen, isNotEmpty, reason: 'sigue habiendo obstáculos en los otros carriles');
    for (final o in seen) {
      expect(o.lane, isNot(1.0), reason: 'el carril del camión está cerrado');
      expect(
        o.kind,
        anyOf(ObstacleKind.lowBarrier, ObstacleKind.overhead),
        reason: 'con un camión solo nacen obstáculos que se pasan en su carril',
      );
    }
  });

  testWidgets('reiniciar saca los camiones y suelta al corredor', (tester) async {
    final state = GameState();
    final game = _game(state);
    await tester.pumpWidget(GameWidget(game: game));

    game.spawnTruck(lane: 1);
    game.player.groundHeight = 40;
    expect(game.trucks, hasLength(1));

    game.restartRun();
    expect(game.trucks, isEmpty);
    expect(game.player.groundHeight, 0);
  });
}
