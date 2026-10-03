import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/perspective.dart';

void main() {
  const p = Perspective(width: 400, height: 800);

  group('Perspective – profundidad', () {
    test('t = 0 vive en el horizonte y t = 1 en la línea base', () {
      expect(p.yAtT(0), p.vanishY);
      expect(p.yAtT(1), closeTo(p.height, 1e-9));
      expect(p.tAtY(p.vanishY), 0);
      expect(p.tAtY(p.height), 1);
    });

    test('t y y se convierten de ida y vuelta', () {
      for (final t in [0.0, 0.25, 0.5, 0.837, 1.0]) {
        expect(p.tAtY(p.yAtT(t)), closeTo(t, 1e-9));
      }
    });

    test('la escala crece con la profundidad', () {
      expect(p.scaleAtT(0.2), 0.2);
      expect(p.scaleAtT(1), 1);
      expect(p.scaleAtT(0.2), lessThan(p.scaleAtT(0.8)));
    });
  });

  group('Perspective – corredor', () {
    test('todos los carriles convergen al punto de fuga en el horizonte', () {
      for (final lane in [-1.0, -0.3, 0.0, 0.5, 1.0]) {
        expect(p.xAtT(lane, 0), p.vanishX);
      }
    });

    test('los carriles ±1 coinciden con los bordes del corredor en la base',
        () {
      expect(p.xAtT(-1, 1), closeTo(p.baseLeftX, 1e-9));
      expect(p.xAtT(1, 1), closeTo(p.baseRightX, 1e-9));
    });

    test('el corredor se ensancha hacia el jugador (divergencia)', () {
      expect(p.xAtT(1, 0.2), lessThan(p.xAtT(1, 0.8)));
      expect(p.xAtT(-1, 0.2), greaterThan(p.xAtT(-1, 0.8)));
      final lejos = p.xAtT(1, 0.2) - p.xAtT(-1, 0.2);
      final cerca = p.xAtT(1, 0.8) - p.xAtT(-1, 0.8);
      expect(lejos, lessThan(cerca));
    });

    test('clampToCorridor mantiene al jugador dentro de las paredes', () {
      final y = p.height * 0.86;
      final t = p.tAtY(y);
      final minX = p.xAtT(-1, t);
      final maxX = p.xAtT(1, t);

      expect(p.clampToCorridor(0, y), minX);
      expect(p.clampToCorridor(p.width, y), maxX);

      final dentro = p.width * 0.5;
      expect(p.clampToCorridor(dentro, y), dentro);
    });
  });
}
