import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/map_renderer.dart';
import 'package:runner_flutter/game/perspective.dart';

void main() {
  const p = Perspective(width: 480, height: 760);

  /// Simula ~2 s de juego para que los props tengan estado real.
  MapRenderer mapEnMarcha() {
    final map = MapRenderer();
    for (var i = 0; i < 120; i++) {
      map.update(1 / 60, 300, p);
    }
    return map;
  }

  SideProp sonda(SideProp b, double z) => SideProp(
        side: b.side,
        z: z,
        widthFrac: b.widthFrac,
        heightFrac: b.heightFrac,
        lateralFrac: b.lateralFrac,
        style: b.style,
      );

  group('Props de la orilla – proyección', () {
    test('hay props en los dos lados de la carretera', () {
      final map = mapEnMarcha();
      expect(map.props, isNotEmpty);
      expect(map.props.where((b) => b.side < 0), isNotEmpty);
      expect(map.props.where((b) => b.side > 0), isNotEmpty);
    });

    test(
        'nunca invaden el asfalto: respetan el hueco mínimo a toda profundidad',
        () {
      for (final b in mapEnMarcha().props) {
        for (var z = 1.0; z <= 4.0; z += 0.2) {
          final probe = sonda(b, z);
          final t = probe.t;
          final r = probe.rect(p);
          final gap = p.baseWidth * SideProp.minGapFrac * t;

          expect(r.width, greaterThan(0), reason: 'ancho nulo en z=$z');
          expect(r.height, greaterThan(0), reason: 'alto nulo en z=$z');
          if (b.side < 0) {
            expect(
              r.right,
              lessThanOrEqualTo(p.xAtT(-1, t) - gap + 1e-9),
              reason: 'prop izquierdo invade la ruta en z=$z',
            );
          } else {
            expect(
              r.left,
              greaterThanOrEqualTo(p.xAtT(1, t) + gap - 1e-9),
              reason: 'prop derecho invade la ruta en z=$z',
            );
          }
        }
      }
    });

    test('la guiñada de cámara tampoco los cruza hacia la ruta', () {
      for (final side in const [-1, 1]) {
        final b = SideProp(
          side: side,
          z: 1.7,
          widthFrac: 0.4,
          heightFrac: 1.0,
          lateralFrac: 0, // lo más cerca de la ruta posible
          style: 0,
        );
        for (final sway in const [-400.0, -120.0, 0.0, 120.0, 400.0]) {
          final t = b.t;
          final r = b.rect(p, sway: sway);
          final gap = p.baseWidth * SideProp.minGapFrac * t;
          if (side < 0) {
            expect(r.right, lessThanOrEqualTo(p.xAtT(-1, t) - gap + 1e-9),
                reason: 'sway=$sway');
          } else {
            expect(r.left, greaterThanOrEqualTo(p.xAtT(1, t) + gap - 1e-9),
                reason: 'sway=$sway');
          }
        }
      }
    });

    test('el hueco mínimo deja el asfalto (más ancho que la ruta) libre', () {
      // La carretera se extiende `roadExtraFrac` hacia afuera de los carriles;
      // los props arrancan más lejos que eso para no pisarla nunca.
      expect(SideProp.minGapFrac, greaterThan(MapRenderer.roadExtraFrac));
    });
  });

  group('Props de la orilla – movimiento', () {
    test('avanzan con el juego y se reciclan sin crecer en memoria', () {
      final map = MapRenderer();
      final cantidadInicial = map.props.length;
      expect(cantidadInicial, greaterThan(0));

      for (var i = 0; i < 3600; i++) {
        map.update(1 / 60, 400, p); // un minuto de carrera
      }

      expect(map.props.length, cantidadInicial);
      for (final b in map.props) {
        expect(b.z, greaterThanOrEqualTo(1.0));
        expect(b.z, lessThan(4.0));
      }
    });

    test('un doble de velocidad duplica el avance en profundidad', () {
      final lento = MapRenderer();
      final rapido = MapRenderer();
      final bLento = lento.props.first;
      final bRapido = rapido.props.first;
      final z0Lento = bLento.z;
      final z0Rapido = bRapido.z;

      for (var i = 0; i < 10; i++) {
        lento.update(1 / 60, 300, p);
        rapido.update(1 / 60, 600, p);
      }

      final avanceLento = z0Lento - bLento.z;
      final avanceRapido = z0Rapido - bRapido.z;
      expect(avanceLento, greaterThan(0), reason: 'el prop debe acercarse');
      expect(avanceRapido, closeTo(avanceLento * 2, 1e-9));
    });

    test('se mantienen ordenados de lejos a cerca (dibujo correcto)', () {
      final map = mapEnMarcha();
      for (var i = 1; i < map.props.length; i++) {
        expect(
          map.props[i - 1].z,
          greaterThanOrEqualTo(map.props[i].z),
          reason: 'los lejanos deben dibujarse primero',
        );
      }
    });

    test('cubren los cinco tipos del desierto entre los dos lados', () {
      final map = MapRenderer();
      final kinds = map.props.map((b) => b.style % 5).toSet();
      expect(kinds, {0, 1, 2, 3, 4});
    });
  });
}
