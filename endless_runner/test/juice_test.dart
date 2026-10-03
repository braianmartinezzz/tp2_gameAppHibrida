import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/coin_component.dart';
import 'package:runner_flutter/game/juice.dart';
import 'package:runner_flutter/game/power_up_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';

const _w = 480;
const _h = 760;

/// Lienzo de trabajo (los literales van aparte: `Size`/`Rect` piden doubles y
/// [_w]/[_h] son enteros para indexar bytes y llamar a `toImage`).
const _surface = Size(480, 760);
const _frame = Rect.fromLTWH(0, 0, 480, 760);

/// Dibuja [draw] en una imagen 480x760 y devuelve sus bytes RGBA (fondo
/// transparente). Requiere `tester.runAsync` por el `toImage`.
Future<Uint8List> _renderRgba(void Function(Canvas canvas) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder));
  final image = await recorder.endRecording().toImage(_w, _h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}

/// Píxeles con alfa > [minAlpha] dentro de un rectángulo de la imagen.
int _countOpaque(
  Uint8List rgba,
  int x0,
  int y0,
  int x1,
  int y1, {
  int minAlpha = 40,
}) {
  var n = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      if (rgba[(y * _w + x) * 4 + 3] > minAlpha) n++;
    }
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('juice (unidad)', () {
    test('la recogida de moneda lanza anillo, chispas y el +1 sin golpes', () {
      final juice = Juice(random: Random(7));
      juice.coinPickup(const Offset(100, 200));

      expect(juice.rings, hasLength(1));
      expect(juice.sparks, hasLength(7));
      expect(juice.labels, hasLength(1));
      expect(juice.labels.single.icon, isNull, reason: 'el +1 no lleva icono');
      expect(juice.shake, 0, reason: 'una moneda no sacude');
      expect(juice.flashAlpha, 0, reason: 'una moneda no destella');
      expect(juice.isIdle, isFalse);
    });

    test('el anillo se expande y todo expira con el tiempo', () {
      final juice = Juice(random: Random(7));
      juice.coinPickup(const Offset(0, 0));
      final radius0 = juice.rings.single.radius;

      juice.update(0.1);
      expect(
        juice.rings.single.radius,
        greaterThan(radius0),
        reason: 'el anillo crece desde que nace',
      );

      var elapsed = 0.1;
      while (!juice.isIdle && elapsed < 5) {
        juice.update(0.05);
        elapsed += 0.05;
      }
      expect(juice.isIdle, isTrue, reason: 'las partículas mueren solas');
    });

    test('las chispas caen con gravedad', () {
      final juice = Juice(random: Random(3));
      juice.hitPaid(Offset.zero);

      final downward = juice.sparks.where((s) => s.vel.dy > 20).toList();
      expect(downward, isNotEmpty);
      final spark = downward.first;
      final y0 = spark.pos.dy;
      final vy0 = spark.vel.dy;

      juice.update(0.05);
      expect(spark.pos.dy, greaterThan(y0));
      expect(spark.vel.dy, greaterThan(vy0), reason: 'la gravedad empuja abajo');
    });

    test('la etiqueta flotante sube desde el punto de recogida', () {
      final juice = Juice(random: Random(7));
      juice.coinPickup(const Offset(0, 300));
      final rise0 = juice.labels.single.rise;
      expect(rise0, 0);

      juice.update(0.2);
      expect(juice.labels.single.rise, greaterThan(rise0));
      expect(juice.labels.single.rise, lessThan(46), reason: 'nunca se pasa');
    });

    test('la sacudida se acota, tiembla y decae a cero', () {
      final juice = Juice();
      juice
        ..addShake(6)
        ..addShake(6)
        ..addShake(6);

      expect(juice.shake, Juice.maxShake, reason: 'nunca pasa del tope');
      expect(juice.shakeOffset, isNot(Offset.zero), reason: 'la cámara se corre');

      juice.update(1);
      expect(juice.shake, 0);
      expect(juice.shakeOffset, Offset.zero);
      expect(juice.isIdle, isTrue);
    });

    test('el destello decae y uno débil no pisa a uno fuerte', () {
      final juice = Juice();
      juice.flash(Juice.hitColor, 0.8, duration: 0.4);
      expect(juice.flashAlpha, 0.8);
      expect(juice.flashColor, Juice.hitColor);

      juice.flash(Juice.shieldColor, 0.2, duration: 0.2);
      expect(juice.flashColor, Juice.hitColor, reason: 'gana el más fuerte');
      expect(juice.flashAlpha, 0.8);

      juice.update(0.4);
      expect(juice.flashAlpha, 0);
      expect(juice.flashColor, isNull);
    });

    test('las listas tienen techo aunque lluevan partículas', () {
      final juice = Juice(random: Random(1));
      for (var i = 0; i < 400; i++) {
        juice.coinPickup(Offset(i.toDouble(), 0));
      }
      expect(juice.rings.length, lessThanOrEqualTo(Juice.maxRings));
      expect(juice.sparks.length, lessThanOrEqualTo(Juice.maxSparks));
      expect(juice.labels.length, lessThanOrEqualTo(Juice.maxLabels));
    });

    test('reset limpia todo para reiniciar la partida', () {
      final juice = Juice(random: Random(1))
        ..death(const Offset(10, 10));
      expect(juice.isIdle, isFalse);

      juice.reset();
      expect(juice.isIdle, isTrue);
      expect(juice.shake, 0);
      expect(juice.flashColor, isNull);
    });
  });

  group('juice en la partida', () {
    testWidgets('recoger una moneda dispara su feedback', (tester) async {
      await tester.binding.setSurfaceSize(_surface);
      final gameState = GameState()..themeMode.value = ThemeMode.dark;
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));

      game.spawnCoinPattern(
        pattern: CoinPattern.line,
        anchorLane: 0,
        avoidObstacles: false,
      );
      for (var i = 0; i < 200 && game.juice.labels.isEmpty; i++) {
        game.powerUps.grantInvulnerability(); // golpes neutralizados
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(game.juice.labels, hasLength(1), reason: 'llegó la moneda');
      expect(game.juice.labels.single.icon, isNull, reason: 'es el +1');
      expect(game.juice.rings, isNotEmpty);
      expect(game.juice.flashAlpha, 0, reason: 'sin golpes no hay destello');
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('saltar y aterrizar levanta polvo en el piso', (tester) async {
      await tester.binding.setSurfaceSize(_surface);
      final gameState = GameState()..themeMode.value = ThemeMode.dark;
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));

      expect(game.player.jump(), isTrue);
      for (var i = 0; i < 80 && game.juice.rings.isEmpty; i++) {
        game.powerUps.grantInvulnerability();
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(game.juice.rings, isNotEmpty, reason: 'el aterrizaje levanta polvo');
      expect(
        game.juice.rings.any((r) => r.flatten < 1),
        isTrue,
        reason: 'el anillo va apoyado en el piso, no es un círculo',
      );
      expect(game.juice.labels, isEmpty, reason: 'el polvo no lleva texto');
      expect(game.juice.flashAlpha, 0, reason: 'golpes neutralizados');
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('recoger un power-up lanza su ficha y destello de color',
        (tester) async {
      await tester.binding.setSurfaceSize(_surface);
      final gameState = GameState()..themeMode.value = ThemeMode.dark;
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));

      final item = game.spawnPowerUp(
        kind: PowerUpKind.multiplier,
        lane: 0,
        avoidObstacles: false,
      );
      expect(item, isNotNull);

      for (var i = 0; i < 400 && !game.powerUps.isMultiplierActive; i++) {
        game.powerUps.grantInvulnerability(); // golpes neutralizados
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        game.powerUps.isMultiplierActive,
        isTrue,
        reason: 'el ítem llegó hasta el jugador',
      );
      expect(
        game.juice.labels.any((l) => l.icon == PowerUpKind.multiplier),
        isTrue,
        reason: 'flota la ficha del poder recogido',
      );
      expect(game.juice.flashColor, PowerUpKind.multiplier.color);
      expect(game.juice.shake, 0, reason: 'recoger un poder no sacude');
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('el escudo absorbe y el destello es azul, no rojo',
        (tester) async {
      await tester.binding.setSurfaceSize(_surface);
      final gameState = GameState()..themeMode.value = ThemeMode.dark;
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));

      expect(game.powerUps.apply(PowerUpKind.shield), isTrue);
      for (var i = 0; i < 1500 && game.powerUps.hasShield; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(game.powerUps.hasShield, isFalse, reason: 'un choque lo gastó');
      expect(game.juice.flashColor, Juice.shieldColor, reason: 'azul del escudo');
      expect(game.juice.shake, greaterThan(0), reason: 'se nota el impacto');
      expect(game.juice.shake, lessThan(Juice.maxShake), reason: 'más suave que la muerte');
      expect(gameState.isGameOver.value, isFalse);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets(
        'tras el golpe final el feedback se disipa y recién ahí se pausa',
        (tester) async {
      await tester.binding.setSurfaceSize(_surface);
      final gameState = GameState()
        ..themeMode.value = ThemeMode.dark
        ..lives.value = 1;
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));

      for (var i = 0; i < 1500 && !gameState.isGameOver.value; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(gameState.isGameOver.value, isTrue, reason: 'con la última vida, el golpe mata');
      final flashAtDeath = game.juice.flashAlpha;
      expect(flashAtDeath, greaterThan(0), reason: 'destello recién nacido');
      final shakeAtDeath = game.juice.shake;
      expect(shakeAtDeath, greaterThan(0));

      // El mundo está congelado, pero el feedback sigue disipándose.
      await tester.pump(const Duration(milliseconds: 200));
      expect(game.juice.shake, lessThan(shakeAtDeath), reason: 'sigue decayendo');
      expect(
        game.juice.flashAlpha,
        lessThan(flashAtDeath),
        reason: 'el destello también se va',
      );
      expect(gameState.isGameOver.value, isTrue);

      // Cuando termina la ventana de gracia todo quedó en cero y el motor
      // quedó pausado: una sacudida nueva ya no se mueve sola.
      for (var i = 0; i < 90 && !game.juice.isIdle; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.juice.isIdle, isTrue, reason: 'nada queda por dibujar');

      // La gracia dura 1.05 s desde el golpe: se espera a que pase del todo
      // para que el motor se pause de verdad antes de sondear.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      game.juice.addShake(6);
      await tester.pump(const Duration(milliseconds: 100));
      expect(game.juice.shake, 6, reason: 'motor pausado: nada lo actualiza');
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('juice en píxeles', () {
    testWidgets('el destello es una viñeta y el +1 se dibuja donde toca',
        (tester) async {
      final flash = Juice()..flash(Juice.hitColor, 0.8);
      final coins = Juice(random: Random(7))
        ..coinPickup(const Offset(240, 380));
      for (var i = 0; i < 6; i++) {
        coins.update(0.03); // ~0.18 s: la etiqueta ya subió un poco
      }

      late Uint8List flashBytes;
      late Uint8List coinBytes;
      await tester.runAsync(() async {
        flashBytes = await _renderRgba(
          (c) => flash.renderFlash(c, _frame),
        );
        coinBytes = await _renderRgba(coins.render);
      });

      // Viñeta: los bordes se tiñen y el centro queda despejado.
      expect(
        _countOpaque(flashBytes, 0, 0, 40, 40),
        greaterThan(100),
        reason: 'la esquina se pinta de rojo',
      );
      expect(
        _countOpaque(flashBytes, 220, 360, 260, 400),
        0,
        reason: 'el centro queda transparente',
      );

      // Recogida: el +1 (que ya subió) pinta píxeles en su zona...
      expect(
        _countOpaque(coinBytes, 215, 340, 270, 395),
        greaterThan(60),
        reason: 'el +1 se dibuja en el punto de recogida',
      );
      // ...y no hay nada suelto en las esquinas.
      expect(
        _countOpaque(coinBytes, 420, 60, 470, 110),
        0,
        reason: 'sin partículas fuera de lugar',
      );
    });
  });
}
