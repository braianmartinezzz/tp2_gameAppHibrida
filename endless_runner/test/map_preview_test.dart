import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/map_renderer.dart';
import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/player_component.dart';

/// Genera un PNG con el mapa + obstáculos + jugador para revisión visual.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generar preview del mapa', () async {
    const w = 480.0;
    const h = 760.0;
    const p = Perspective(width: w, height: h);

    for (final dark in [true, false]) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      final map = MapRenderer();
      // ~3 s de animación para que el fondo y las rayas tengan estado real.
      for (var i = 0; i < 180; i++) {
        map.update(1 / 60, 300, p);
      }
      map.render(canvas, p, dark: dark, playerX: w * 0.5);

      // Obstáculos de los tres tipos a distintas profundidades y carriles.
      final specs = [
        (lane: -1.0, seconds: 0.4, kind: ObstacleKind.lowBarrier),
        (lane: 1.0, seconds: 1.1, kind: ObstacleKind.block),
        (lane: 0.0, seconds: 1.8, kind: ObstacleKind.overhead),
        (lane: -1.0, seconds: 2.4, kind: ObstacleKind.block),
      ];
      for (final s in specs) {
        final o = ObstacleComponent(
          lane: s.lane,
          speed: 300,
          perspective: p,
          kind: s.kind,
        );
        final steps = (s.seconds * 60).round();
        for (var i = 0; i < steps; i++) {
          o.update(1 / 60);
        }
        canvas.save();
        // anchor: topLeft → la caja empieza exactamente en `position`.
        canvas.translate(o.position.x, o.position.y);
        o.render(canvas);
        canvas.restore();
      }

      // Jugador en el carril central, apoyado (lane 0 = eje del corredor).
      final player = PlayerComponent(
        startPosition: Vector2(w * 0.5, h * 0.86),
        perspective: p,
      );
      player.update(0);
      canvas.save();
      canvas.translate(
        player.position.x - player.size.x / 2,
        player.position.y - player.size.y / 2,
      );
      player.render(canvas);
      canvas.restore();

      final picture = recorder.endRecording();
      final image = await picture.toImage(w.toInt(), h.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final path = 'build/map_preview_${dark ? 'dark' : 'light'}.png';
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      debugPrint('guardado: $path');
    }
  });
}
