import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/map_renderer.dart';
import 'package:runner_flutter/game/perspective.dart';

/// Biomas por distancia, props nuevos y detalles del asfalto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const w = 480;
  const h = 760;
  const p = Perspective(width: 480, height: 760);

  /// Corre el mapa a 600 px/s hasta superar [distance] px de mundo.
  MapRenderer avanzarHasta(double distance, {bool props = true}) {
    final map = MapRenderer()..drawProps = props;
    while (map.distance < distance) {
      map.update(1 / 60, 600, p);
    }
    return map;
  }

  /// Tipo de prop (0..10): el paso de estilo es 15.
  Set<int> tipos(MapRenderer map) => map.props.map((b) => b.style % 15).toSet();

  Future<Uint8List> render(MapRenderer map, {required bool dark}) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    map.render(canvas, p, blend: dark ? 1.0 : 0.0, playerX: w * 0.5);
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List();
  }

  List<int> pixel(Uint8List px, int x, int y) {
    final i = (y * w + x) * 4;
    return [px[i], px[i + 1], px[i + 2]];
  }

  group('biomeAt', () {
    test('arranca en el desierto, sin mezcla', () {
      final b = MapRenderer.biomeAt(0);
      expect(b.from, Biome.desert);
      expect(b.to, Biome.ruins);
      expect(b.mix, 0);
    });

    test('la mezcla empieza al final del tramo y llega a la mitad en el medio',
        () {
      const len = MapRenderer.biomeLength;
      const blend = MapRenderer.biomeBlend;
      expect(MapRenderer.biomeAt(len - blend - 1).mix, 0);
      final mitad = MapRenderer.biomeAt(len - blend / 2);
      expect(mitad.from, Biome.desert);
      expect(mitad.mix, closeTo(0.5, 1e-9));
    });

    test('la mezcla no retrocede y termina en 1 antes del siguiente bioma', () {
      const len = MapRenderer.biomeLength;
      var anterior = 0.0;
      for (var d = len - MapRenderer.biomeBlend; d < len; d += 25) {
        final m = MapRenderer.biomeAt(d).mix;
        expect(m, greaterThanOrEqualTo(anterior));
        anterior = m;
      }
      expect(anterior, greaterThan(0.95));
      final despues = MapRenderer.biomeAt(len);
      expect(despues.from, Biome.ruins);
      expect(despues.mix, 0);
    });

    test('rotan desierto → ruinas → cañón → desierto', () {
      const len = MapRenderer.biomeLength;
      expect(MapRenderer.biomeAt(len * 0 + 10).from, Biome.desert);
      expect(MapRenderer.biomeAt(len * 1 + 10).from, Biome.ruins);
      expect(MapRenderer.biomeAt(len * 2 + 10).from, Biome.canyon);
      expect(MapRenderer.biomeAt(len * 3 + 10).from, Biome.desert);
    });
  });

  group('props por bioma', () {
    test('al arrancar son los del desierto', () {
      expect(tipos(MapRenderer()), {0, 1, 2, 3, 4});
    });

    test('al entrar a las ruinas los props nuevos son de ruinas', () {
      final map = avanzarHasta(MapRenderer.biomeLength + 5000);
      expect(map.currentBiome, Biome.ruins);
      final t = tipos(map);
      expect(t.difference({4, 5, 6, 7, 8, 9}), isEmpty,
          reason: 'solo tipos de ruinas: $t');
      expect(t.intersection({5, 6, 7, 8, 9}), isNotEmpty);
    });

    test('en el cañón aparecen los pilares de roca', () {
      final map = avanzarHasta(MapRenderer.biomeLength * 2 + 5000);
      expect(map.currentBiome, Biome.canyon);
      final t = tipos(map);
      expect(t.difference({1, 2, 3, 4, 10}), isEmpty, reason: 'tipos: $t');
      expect(t, contains(10));
    });

    test('los props nuevos nunca invaden el asfalto', () {
      for (final distancia in [
        MapRenderer.biomeLength + 5000,
        MapRenderer.biomeLength * 2 + 5000,
      ]) {
        for (final b in avanzarHasta(distancia).props) {
          for (var z = 1.0; z <= 4.0; z += 0.2) {
            final probe = SideProp(
              side: b.side,
              z: z,
              widthFrac: b.widthFrac,
              heightFrac: b.heightFrac,
              lateralFrac: b.lateralFrac,
              style: b.style,
            );
            final t = probe.t;
            final r = probe.rect(p);
            final gap = p.baseWidth * SideProp.minGapFrac * t;
            if (b.side < 0) {
              expect(r.right, lessThanOrEqualTo(p.xAtT(-1, t) - gap + 1e-9));
            } else {
              expect(r.left, greaterThanOrEqualTo(p.xAtT(1, t) + gap - 1e-9));
            }
          }
        }
      }
    });

    test('se mantienen ordenados de lejos a cerca y no crecen en cantidad', () {
      final map = MapRenderer();
      final inicial = map.props.length;
      final lista = avanzarHasta(MapRenderer.biomeLength * 3).props;
      expect(lista.length, inicial);
      for (var i = 1; i < lista.length; i++) {
        expect(lista[i - 1].z, greaterThanOrEqualTo(lista[i].z));
      }
    });

    test('resetRun vuelve al desierto y a los props iniciales', () {
      final map = avanzarHasta(MapRenderer.biomeLength + 5000);
      expect(map.currentBiome, Biome.ruins);
      map.resetRun();
      expect(map.distance, 0);
      expect(map.currentBiome, Biome.desert);
      expect(tipos(map), {0, 1, 2, 3, 4});
    });
  });

  group('detalles del asfalto', () {
    test('la cantidad es constante y viven dentro de la ruta', () {
      final map = MapRenderer();
      final inicial = map.decalCount;
      expect(inicial, greaterThan(0));
      for (var i = 0; i < 3600; i++) {
        map.update(1 / 60, 400, p);
      }
      expect(map.decalCount, inicial);
      for (final d in map.decalSpots) {
        expect(d.z, greaterThanOrEqualTo(1.0));
        expect(d.z, lessThan(4.0));
        expect(d.lane.abs(), lessThanOrEqualTo(1.1));
      }
    });

    test('solo pintan sobre el asfalto (nunca sobre la arena)', () async {
      // Mismo estado, con y sin detalles: las diferencias tienen que caer
      // dentro de la banda del asfalto.
      final con = MapRenderer();
      final sin = MapRenderer()..drawDecals = false;
      for (var i = 0; i < 240; i++) {
        con.update(1 / 60, 300, p);
        sin.update(1 / 60, 300, p);
      }
      final a = await render(con, dark: false);
      final b = await render(sin, dark: false);

      var cambios = 0;
      var fuera = 0;
      for (var y = 0; y < h; y += 2) {
        final t = p.tAtY(y.toDouble());
        final roadL =
            p.vanishX - p.baseWidth * t * (0.5 + MapRenderer.roadExtraFrac);
        final roadR =
            p.vanishX + p.baseWidth * t * (0.5 + MapRenderer.roadExtraFrac);
        for (var x = 0; x < w; x += 2) {
          final i = (y * w + x) * 4;
          if (a[i] == b[i] && a[i + 1] == b[i + 1] && a[i + 2] == b[i + 2]) {
            continue;
          }
          cambios++;
          if (x < roadL - 2 || x > roadR + 2) fuera++;
        }
      }
      expect(cambios, greaterThan(0), reason: 'los detalles deben verse');
      expect(fuera, 0, reason: 'ningún detalle puede salirse del asfalto');
    });
  });

  group('render por bioma', () {
    test('cada bioma pinta la arena con su color, en día y en noche', () async {
      for (final dark in [false, true]) {
        final colores = <List<int>>[];
        for (var k = 0; k < 3; k++) {
          final map =
              avanzarHasta(MapRenderer.biomeLength * k + 500, props: false);
          final px = await render(map, dark: dark);
          // Arena a la izquierda, bajo el horizonte, fuera del asfalto.
          colores.add(pixel(px, 4, (p.vanishY + 120).round()));

          var transparentes = 0;
          for (var i = 3; i < px.length; i += 4) {
            if (px[i] != 255) transparentes++;
          }
          expect(transparentes, 0, reason: 'bioma $k: todo debe quedar opaco');
        }
        expect(colores[0], isNot(colores[1]), reason: 'desierto vs ruinas');
        expect(colores[1], isNot(colores[2]), reason: 'ruinas vs cañón');
        expect(colores[0], isNot(colores[2]), reason: 'desierto vs cañón');
      }
    });

    test('en plena mezcla el color queda entre los dos biomas', () async {
      final desierto = pixel(
        await render(avanzarHasta(500, props: false), dark: false),
        4,
        (p.vanishY + 120).round(),
      );
      final ruinas = pixel(
        await render(
          avanzarHasta(MapRenderer.biomeLength + 500, props: false),
          dark: false,
        ),
        4,
        (p.vanishY + 120).round(),
      );
      final medio = pixel(
        await render(
          avanzarHasta(
            MapRenderer.biomeLength - MapRenderer.biomeBlend / 2,
            props: false,
          ),
          dark: false,
        ),
        4,
        (p.vanishY + 120).round(),
      );
      for (var c = 0; c < 3; c++) {
        final lo = desierto[c] < ruinas[c] ? desierto[c] : ruinas[c];
        final hi = desierto[c] > ruinas[c] ? desierto[c] : ruinas[c];
        expect(medio[c], inInclusiveRange(lo - 3, hi + 3),
            reason: 'canal $c: $desierto → $medio → $ruinas');
      }
    });
  });
}
