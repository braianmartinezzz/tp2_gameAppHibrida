import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/chase_horde.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';

const _p = Perspective(width: 480, height: 760);

/// Avanza la horda [seconds] en pasos de 1/60 s.
void _run(ChaseHorde horde, double seconds) {
  const step = 1 / 60;
  for (var t = 0.0; t < seconds && !horde.caught; t += step) {
    horde.update(step);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChaseHorde: estado', () {
    test('arranca a distancia segura y sin atrapar', () {
      final horde = ChaseHorde();
      expect(horde.gap, ChaseHorde.startGap);
      expect(horde.level, 0);
      expect(horde.caught, isFalse);
    });

    test('al principio el corredor se despega solo hasta la distancia máxima',
        () {
      final horde = ChaseHorde();
      _run(horde, 20);
      expect(horde.gap, ChaseHorde.maxGap);
      expect(horde.caught, isFalse);
    });

    test('la horda acelera cada levelEvery segundos y tiene tope', () {
      final horde = ChaseHorde();
      var lastSpeed = horde.speed;
      var levelUps = 0;
      const step = 1 / 60;
      for (var t = 0.0; t < ChaseHorde.levelEvery * 20; t += step) {
        if (horde.update(step)) {
          levelUps++;
          expect(horde.speed, greaterThanOrEqualTo(lastSpeed));
          lastSpeed = horde.speed;
        }
        if (horde.caught) break;
      }
      expect(levelUps, greaterThan(0));
      expect(horde.speed, lessThanOrEqualTo(ChaseHorde.maxSpeed));
    });

    test('update avisa del cambio de nivel exactamente una vez', () {
      final horde = ChaseHorde();
      var flagged = 0;
      for (var i = 0; i < (ChaseHorde.levelEvery * 60).round() + 5; i++) {
        if (horde.update(1 / 60)) flagged++;
      }
      expect(horde.level, 1);
      expect(flagged, 1);
    });

    test('a nivel alto la horda gana terreno aunque no haya errores', () {
      final horde = ChaseHorde()..level = 12;
      expect(horde.netRecovery, lessThan(0));
      _run(horde, 120);
      expect(horde.caught, isTrue);
    });

    test('tropezar acerca la horda y varios tropiezos seguidos la atrapan', () {
      final horde = ChaseHorde()..gap = ChaseHorde.maxGap;
      horde.stumble();
      expect(horde.gap, closeTo(ChaseHorde.maxGap - ChaseHorde.stumblePenalty, 1e-9));
      expect(horde.caught, isFalse);

      horde
        ..stumble()
        ..stumble()
        ..stumble();
      expect(horde.caught, isTrue);
    });

    test('atrapado es pegajoso: la recuperación del mismo frame no lo deshace',
        () {
      final horde = ChaseHorde()..gap = 0.1;
      horde.stumble();
      expect(horde.caught, isTrue);
      horde.update(1 / 60);
      expect(horde.caught, isTrue);
    });

    test('los diamantes la alejan, con tope por pickup y sin pasar de maxGap',
        () {
      final horde = ChaseHorde()..gap = 0.5;
      horde.relieve(1);
      expect(horde.gap, closeTo(0.5 + ChaseHorde.pickupRelief, 1e-9));

      horde.gap = 0.5;
      horde.relieve(100);
      expect(horde.gap, closeTo(0.5 + ChaseHorde.maxPickupRelief, 1e-9));

      horde.gap = 0.99;
      horde.relieve(100);
      expect(horde.gap, ChaseHorde.maxGap);
    });

    test('reset deja la horda como al inicio', () {
      final horde = ChaseHorde()..level = 7;
      horde
        ..gap = 0
        ..caught = true
        ..elapsed = 99;
      horde.reset();
      expect(horde.gap, ChaseHorde.startGap);
      expect(horde.level, 0);
      expect(horde.elapsed, 0);
      expect(horde.caught, isFalse);
    });
  });

  group('ChaseHorde: geometría', () {
    final horde = ChaseHorde();
    final feet = _p.height * 0.86 + 17;

    test('la horda crece al acercarse', () {
      final far = horde.zombieHeight(_p, feet, 1.0);
      final mid = horde.zombieHeight(_p, feet, 0.5);
      final near = horde.zombieHeight(_p, feet, 0.0);
      expect(mid, greaterThan(far));
      expect(near, greaterThan(mid));
      expect(near / far, closeTo(ChaseHorde.maxLooming, 1e-9));
    });

    test('el frente sube por la pantalla y en gap 0 toca los pies del corredor',
        () {
      final far = horde.frontFeetY(_p, feet, 1.0);
      final mid = horde.frontFeetY(_p, feet, 0.5);
      final line = horde.frontFeetY(_p, feet, 0.0);
      expect(far, greaterThan(_p.height), reason: 'lejos: solo asoman cabezas');
      expect(mid, lessThan(far));
      expect(line, closeTo(feet, 1e-9), reason: 'la línea de Game Over');
    });
  });

  group('RunnerGame con horda', () {
    testWidgets('que la horda alcance al corredor termina la partida',
        (tester) async {
      final gameState = GameState();
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));
      expect(gameState.isGameOver.value, isFalse);

      // Tropiezos seguidos: la horda queda encima.
      for (var i = 0; i < 4; i++) {
        game.horde.stumble();
      }
      await tester.pump(const Duration(milliseconds: 16));

      expect(gameState.isGameOver.value, isTrue);
    });

    testWidgets('con la horda apagada el corredor no muere por ella',
        (tester) async {
      final gameState = GameState();
      final game = RunnerGame(gameState: gameState, hordeEnabled: false, zombiesEnabled: false);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));

      game.horde.caught = true;
      await tester.pump(const Duration(milliseconds: 16));

      expect(gameState.isGameOver.value, isFalse);
    });

    testWidgets('la horda corre mientras se juega y reiniciar la resetea',
        (tester) async {
      final gameState = GameState()..lives.value = 1000000;
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.horde.elapsed, greaterThan(0));

      game.horde.level = 3;
      game.restartRun();
      expect(game.horde.level, 0);
      expect(game.horde.gap, ChaseHorde.startGap);
      expect(game.horde.caught, isFalse);
    });

    testWidgets('en el tutorial no hay horda (no corre ni mata)',
        (tester) async {
      final gameState = GameState();
      final game = RunnerGame(gameState: gameState)..tutorialActive = true;
      await tester.pumpWidget(GameWidget(game: game));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(game.horde.elapsed, 0);
      expect(gameState.isGameOver.value, isFalse);
    });

    testWidgets('la horda se dibuja en el borde inferior y crece al acercarse',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final gameState = GameState()..lives.value = 1000000;
      final game = RunnerGame(gameState: gameState);
      await tester.pumpWidget(GameWidget(game: game));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      Future<Uint8List> shot() async {
        final recorder = ui.PictureRecorder();
        game.render(Canvas(recorder));
        final image = await recorder.endRecording().toImage(480, 760);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return bytes!.buffer.asUint8List();
      }

      int diffInBand(Uint8List a, Uint8List b, int y0, int y1) {
        var n = 0;
        for (var y = y0; y < y1; y++) {
          for (var x = 0; x < 480; x++) {
            final i = (y * 480 + x) * 4;
            if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
              n++;
            }
          }
        }
        return n;
      }

      late Uint8List without;
      late Uint8List farHorde;
      late Uint8List nearHorde;
      await tester.runAsync(() async {
        game.hordeEnabled = false;
        without = await shot();
        game.hordeEnabled = true;
        game.horde.gap = 1.0;
        farHorde = await shot();
        game.horde.gap = 0.1;
        nearHorde = await shot();
      });

      final farPx = diffInBand(without, farHorde, 600, 760);
      final nearPx = diffInBand(without, nearHorde, 600, 760);
      expect(farPx, greaterThan(0), reason: 'asoman cabezas en el borde inferior');
      expect(nearPx, greaterThan(farPx), reason: 'cerca ocupa más pantalla');
    });
  });
}
