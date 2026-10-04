import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/map_renderer.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/speed_rumble.dart';

/// Capa de ciudad del parallax y temblor de cámara por velocidad.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const w = 480;
  const h = 760;
  const p = Perspective(width: 480, height: 760);

  group('SpeedRumble', () {
    test('no hay temblor al arrancar ni por debajo de la velocidad base', () {
      for (final speed in [0.0, 100.0, SpeedRumble.baseSpeed]) {
        expect(SpeedRumble.intensity(speed), 0);
        expect(SpeedRumble.amplitude(speed), 0);
        for (var t = 0.0; t < 2; t += 0.1) {
          expect(SpeedRumble.offsetAt(t, speed), ui.Offset.zero);
        }
      }
    });

    test('crece con la velocidad y se queda en el máximo', () {
      var anterior = 0.0;
      for (var s = 260.0; s <= 640; s += 20) {
        final a = SpeedRumble.amplitude(s);
        expect(a, greaterThanOrEqualTo(anterior));
        anterior = a;
      }
      expect(SpeedRumble.amplitude(SpeedRumble.fullSpeed),
          closeTo(SpeedRumble.maxAmplitude, 1e-9));
      expect(SpeedRumble.amplitude(5000),
          closeTo(SpeedRumble.maxAmplitude, 1e-9));
    });

    test('el desplazamiento nunca supera la amplitud (cota para el overscan)',
        () {
      for (final speed in [300.0, 450.0, 640.0, 900.0]) {
        final amp = SpeedRumble.amplitude(speed);
        var maxDy = 0.0;
        for (var t = 0.0; t < 20; t += 0.007) {
          final o = SpeedRumble.offsetAt(t, speed);
          expect(o.dx.abs(), lessThanOrEqualTo(amp + 1e-9));
          expect(o.dy.abs(), lessThanOrEqualTo(amp + 1e-9));
          maxDy = max(maxDy, o.dy.abs());
        }
        expect(maxDy, greaterThan(amp * 0.5), reason: 'el temblor se nota');
      }
    });

    test('es determinista y mueve más en vertical que en horizontal', () {
      expect(SpeedRumble.offsetAt(3.3, 600), SpeedRumble.offsetAt(3.3, 600));
      var sumX = 0.0;
      var sumY = 0.0;
      for (var t = 0.0; t < 10; t += 0.01) {
        final o = SpeedRumble.offsetAt(t, 640);
        sumX += o.dx.abs();
        sumY += o.dy.abs();
      }
      expect(sumY, greaterThan(sumX));
    });
  });

  group('peso de la ciudad por bioma', () {
    test('tenue en el desierto, plena en las ruinas y nula en el cañón', () {
      expect(MapRenderer.cityWeight(0), closeTo(0.3, 1e-9));
      expect(MapRenderer.cityWeight(MapRenderer.biomeLength + 500), 1.0);
      expect(MapRenderer.cityWeight(MapRenderer.biomeLength * 2 + 500), 0.0);
    });

    test('la transición entre biomas es continua (sin saltos)', () {
      var anterior = MapRenderer.cityWeight(0);
      for (var d = 0.0; d < MapRenderer.biomeLength * 3; d += 20) {
        final actual = MapRenderer.cityWeight(d);
        expect((actual - anterior).abs(), lessThan(0.05), reason: 'd=$d');
        anterior = actual;
      }
    });
  });

  group('siluetas de ciudad', () {
    MapRenderer enDistancia(double distance, {required bool skyline}) {
      final map = MapRenderer()..drawSkyline = skyline;
      while (map.distance < distance) {
        map.update(1 / 60, 600, p);
      }
      return map;
    }

    Future<Uint8List> render(MapRenderer map, {required double blend}) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      map.render(canvas, p, blend: blend, playerX: w * 0.5);
      final image = await recorder.endRecording().toImage(w, h);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return bytes!.buffer.asUint8List();
    }

    /// Píxeles distintos entre dos renders: (cantidad, y más baja tocada).
    ({int cambios, int maxY, int calidos}) diff(Uint8List a, Uint8List b) {
      var cambios = 0;
      var maxY = -1;
      var calidos = 0;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          if (a[i] == b[i] && a[i + 1] == b[i + 1] && a[i + 2] == b[i + 2]) {
            continue;
          }
          cambios++;
          if (y > maxY) maxY = y;
          // Ventana encendida: mucho más roja que azul.
          if (a[i] - a[i + 2] > 100) calidos++;
        }
      }
      return (cambios: cambios, maxY: maxY, calidos: calidos);
    }

    test('en las ruinas se dibuja y nunca baja del horizonte', () async {
      final d = MapRenderer.biomeLength + 500;
      final con = await render(enDistancia(d, skyline: true), blend: 0);
      final sin = await render(enDistancia(d, skyline: false), blend: 0);
      final r = diff(con, sin);
      expect(r.cambios, greaterThan(300), reason: 'la ciudad debe verse');
      expect(r.maxY, lessThanOrEqualTo(p.vanishY.ceil() + 1),
          reason: 'los edificios apoyan en el horizonte');
    });

    test('en el cañón no hay ciudad', () async {
      final d = MapRenderer.biomeLength * 2 + 500;
      final con = await render(enDistancia(d, skyline: true), blend: 0);
      final sin = await render(enDistancia(d, skyline: false), blend: 0);
      expect(diff(con, sin).cambios, 0);
    });

    test('de noche aparecen ventanas encendidas; de día no', () async {
      final d = MapRenderer.biomeLength + 500;
      final noche = diff(
        await render(enDistancia(d, skyline: true), blend: 1),
        await render(enDistancia(d, skyline: false), blend: 1),
      );
      final dia = diff(
        await render(enDistancia(d, skyline: true), blend: 0),
        await render(enDistancia(d, skyline: false), blend: 0),
      );
      expect(noche.calidos, greaterThan(0), reason: 'faltan ventanas de noche');
      expect(dia.calidos, 0);
    });

    test('la ciudad se mueve con el parallax (distinto frame, distinto dibujo)',
        () async {
      final d = MapRenderer.biomeLength + 500;
      final a = enDistancia(d, skyline: true);
      final antes = await render(a, blend: 0);
      for (var i = 0; i < 60; i++) {
        a.update(1 / 60, 600, p);
      }
      final despues = await render(a, blend: 0);
      expect(diff(antes, despues).cambios, greaterThan(0));
    });
  });
}
