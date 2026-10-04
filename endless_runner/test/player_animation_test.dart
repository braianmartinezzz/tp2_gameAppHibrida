import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/player_component.dart';

const _p = Perspective(width: 480, height: 760);

PlayerComponent _player() => PlayerComponent(
      startPosition: Vector2(_p.width * 0.5, _p.height * 0.86),
      perspective: _p,
    );

/// Avanza [seconds] en pasos de 1/120 s, igual que el resto de las pruebas.
void _advance(PlayerComponent p, double seconds) {
  const step = 1 / 120;
  for (var t = 0.0; t < seconds; t += step) {
    p.update(step);
  }
}

// Índices del atlas (ver tools/build_player_atlas.py).
const _runRange = [0, 7];
const _jumpCrouch = 8, _jumpRise = 9, _jumpApex = 10, _jumpFall = 11;
const _landing = 12;
const _slideIn = 13, _slideA = 14, _slideB = 15, _slideOut = 16;

void main() {
  group('carrera', () {
    test('parado en el suelo usa los cuadros de carrera y los recorre todos',
        () {
      final p = _player();
      final seen = <int>{};
      for (var i = 0; i < 240; i++) {
        p.update(1 / 120);
        seen.add(p.poseFrame);
      }
      expect(seen.every((f) => f >= _runRange[0] && f <= _runRange[1]), isTrue);
      expect(seen.length, 8, reason: 'recorre el ciclo completo en 2 s');
    });

    test('corre más rápido cuanto más rápido va el mundo', () {
      int framesDistinct(double rate) {
        final p = _player()..runRate = rate;
        final seen = <int>{};
        for (var i = 0; i < 24; i++) {
          p.update(1 / 120); // 0.2 s
          seen.add(p.poseFrame);
        }
        return seen.length;
      }

      expect(framesDistinct(1.9), greaterThan(framesDistinct(1.0)));
    });

    test('no se inclina de costado corriendo recto', () {
      final p = _player();
      p.update(1 / 120);
      final x0 = p.position.x;
      _advance(p, 2);
      expect(p.lean, 0);
      expect(p.position.x, closeTo(x0, 0.001),
          reason: 'sin balanceo lateral del cuerpo');
    });

    test('se inclina hacia donde cambia de carril y se endereza solo', () {
      final p = _player()..moveLane(1);
      p.update(1 / 120);
      p.update(1 / 120);
      expect(p.lean, greaterThan(0), reason: 'derecha = inclina a la derecha');
      _advance(p, 0.6);
      expect(p.lean.abs(), lessThan(0.01));

      p.moveLane(-1);
      p.moveLane(-1);
      p.update(1 / 120);
      p.update(1 / 120);
      expect(p.lean, lessThan(0));
    });
  });

  group('salto', () {
    test('pasa por impulso, subida, punto más alto, caída y aterrizaje', () {
      final p = _player()..jump();
      final order = <int>[];
      void record() {
        if (order.isEmpty || order.last != p.poseFrame) order.add(p.poseFrame);
      }

      record();
      const step = 1 / 240;
      for (var t = 0.0; t < 1.2; t += step) {
        p.update(step);
        record();
      }

      expect(order.take(5).toList(),
          [_jumpCrouch, _jumpRise, _jumpApex, _jumpFall, _landing]);
      expect(_runRange.first <= order.last && order.last <= _runRange.last,
          isTrue, reason: 'termina de nuevo corriendo');
    });

    test('la pose de aterrizaje dura un instante', () {
      final p = _player()..jump();
      while (p.isAirborne) {
        p.update(1 / 240);
      }
      expect(p.poseFrame, _landing);
      _advance(p, 0.2);
      expect(p.poseFrame, lessThanOrEqualTo(7));
    });
  });

  group('agachado', () {
    test('entra, desliza alternando dos cuadros y sale', () {
      final p = _player()..roll();
      expect(p.poseFrame, _slideIn);

      final middle = <int>{};
      const step = 1 / 120;
      var t = 0.0;
      while (t < PlayerComponent.rollDuration * 0.7) {
        p.update(step);
        t += step;
        if (t > PlayerComponent.rollDuration * 0.25) middle.add(p.poseFrame);
      }
      expect(middle, {_slideA, _slideB});

      while (p.isRolling && t < 2) {
        p.update(step);
        t += step;
        if (p.rollTimer > 0 &&
            p.rollTimer < PlayerComponent.rollDuration * 0.1) {
          expect(p.poseFrame, _slideOut);
        }
      }
      expect(p.isRolling, isFalse);
      expect(p.poseFrame, lessThanOrEqualTo(7));
    });

    test('agacharse en el aire cae encogido y rueda al tocar el suelo', () {
      final p = _player()..jump();
      _advance(p, 0.12);
      expect(p.isAirborne, isTrue);

      p.roll();
      p.update(1 / 120);
      expect(p.poseFrame, _slideIn, reason: 'en picada, ya encogido');

      while (p.isAirborne) {
        p.update(1 / 240);
      }
      expect(p.isRolling, isTrue);
      expect(p.poseFrame, anyOf(_slideIn, _slideA, _slideB));
    });

    test('la caja de colisión no cambia con la animación', () {
      final p = _player();
      expect(p.hitBox.height, PlayerComponent.playerSize);
      p.roll();
      expect(p.hitBox.height, PlayerComponent.rollHeight);
    });
  });

  group('dibujo', () {
    test('sin arte cargado (fallback) dibuja sin fallar en todas las poses', () {
      final p = _player();
      void draw() {
        final recorder = ui.PictureRecorder();
        p.render(ui.Canvas(recorder));
        recorder.endRecording();
      }

      draw();
      p.jump();
      _advance(p, 0.15);
      draw();
      while (p.isAirborne) {
        p.update(1 / 120);
      }
      p.roll();
      _advance(p, 0.1);
      draw();
    });

    test('resetTo deja la animación en el estado inicial', () {
      final p = _player()..runRate = 1.8;
      p.moveLane(1);
      p.jump();
      _advance(p, 0.2);
      p.resetTo(startPosition: Vector2(_p.width * 0.5, _p.height * 0.86));
      expect(p.runRate, 1);
      expect(p.lean, 0);
      expect(p.poseFrame, 0);
    });
  });
}
