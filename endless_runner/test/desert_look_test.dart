import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/map_renderer.dart';
import 'package:runner_flutter/game/perspective.dart';

/// Look 🏜️: el mapa tiene que leerse como una carretera sobre el desierto.
///
/// Estos tests miran el render píxel a píxel (no la geometría, que ya cubre
/// `map_props_test`): asfalto más oscuro que la arena, divisorias pintadas y
/// discontinuas, props siempre fuera del asfalto y tema que ilumina o apaga
/// la escena.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const w = 480;
  const h = 760;
  const p = Perspective(width: 480, height: 760);

  /// Renderiza el mapa tras ~3 s de animación y devuelve los bytes RGBA.
  Future<Uint8List> render({
    required bool dark,
    bool withProps = true,
    int frames = 180,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final map = MapRenderer()..drawProps = withProps;
    for (var i = 0; i < frames; i++) {
      map.update(1 / 60, 300, p);
    }
    map.render(canvas, p, dark: dark, playerX: w * 0.5);
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return bytes!.buffer.asUint8List();
  }

  /// Luminancia aproximada de un píxel (los bytes son RGBA).
  int luma(Uint8List px, int x, int y) {
    final i = (y * w + x) * 4;
    return (0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]).round();
  }

  /// Ancho exterior de la zona de arena a una altura: el borde del hombro de
  /// grava (más afuera no hay asfalto ni grava: solo desierto).
  double arenaMaxEn(double y) {
    final t = p.tAtY(y);
    return p.vanishX -
        p.baseWidth * t * (0.5 + MapRenderer.roadExtraFrac + MapRenderer.shoulderFrac);
  }

  /// Centro X del asfalto a una altura (los divisores nunca lo tocan).
  double asfaltoEn(double y) => p.vanishX;

  test('el asfalto se lee más oscuro que la arena en los dos temas', () async {
    for (final dark in [false, true]) {
      final px = await render(dark: dark, withProps: false);

      final diffs = <int>[];
      for (var y = p.vanishY.round() + 40; y < h - 6; y += 6) {
        // Filas donde la arena asoma a los costados (más abajo el asfalto
        // llega a los bordes de la pantalla y no hay arena que medir).
        if (arenaMaxEn(y.toDouble()) < 12) continue;
        final sand = luma(px, 4, y);
        final road = luma(px, asfaltoEn(y.toDouble()).round(), y);
        diffs.add(sand - road);
      }

      expect(diffs, isNotEmpty, reason: 'debería haber filas con arena visible');

      final ordenados = [...diffs]..sort();
      final mediana = ordenados[ordenados.length ~/ 2];
      final positivas = diffs.where((d) => d > 0).length / diffs.length;

      expect(
        mediana,
        greaterThan(4),
        reason: 'en la fila típica la arena debe clara y el asfalto oscuro',
      );
      expect(
        positivas,
        greaterThanOrEqualTo(0.85),
        reason:
            'casi todas las filas deben respetar arena clara / asfalto oscuro '
            '(solo las bandas de velocidad más la bruma lo emparejan)',
      );
    }
  });

  test('las divisorias están pintadas y se leen discontinuas', () async {
    final px = await render(dark: false);

    var pintadas = 0;
    var huecos = 0;
    for (var y = 0; y < h; y += 5) {
      final t = p.tAtY(y.toDouble());
      if (t < 0.35 || t > 0.9) continue; // zona legible (lejos hay bruma)
      final x = p.xAtT(0.5, t).round();
      // Pintura: el máximo de luminancia en un radio de 2 px sobre la línea.
      var linea = 0;
      for (var d = -2; d <= 2; d++) {
        final v = luma(px, x + d, y);
        if (v > linea) linea = v;
      }
      // Asfalto limpio a 26 px hacia el centro (mismo carril, fuera de la
      // línea): las bandas de velocidad afectan igual a los dos y se anulan.
      final asfalto = luma(px, x - 26, y);
      if (linea > asfalto + 40) {
        pintadas++;
      } else {
        huecos++;
      }
    }

    expect(pintadas, greaterThan(0), reason: 'falta la pintura del divisor');
    expect(huecos, greaterThan(0), reason: 'el divisor debe ser discontinuo');
  });

  test('los props se dibujan siempre fuera del asfalto', () async {
    final conProps = await render(dark: false, withProps: true);
    final sinProps = await render(dark: false, withProps: false);

    var tinta = 0;
    var sobreAsfalto = 0;
    for (var y = 0; y < h; y += 2) {
      final t = p.tAtY(y.toDouble());
      // El asfalto ocupa esta banda a la altura `y` (arriba del horizonte el
      // intervalo queda vacío y ninguna tinta puede caer adentro).
      final roadL =
          p.vanishX - p.baseWidth * t * (0.5 + MapRenderer.roadExtraFrac);
      final roadR =
          p.vanishX + p.baseWidth * t * (0.5 + MapRenderer.roadExtraFrac);
      for (var x = 0; x < w; x += 2) {
        final i = (y * w + x) * 4;
        final cambio = conProps[i] != sinProps[i] ||
            conProps[i + 1] != sinProps[i + 1] ||
            conProps[i + 2] != sinProps[i + 2] ||
            conProps[i + 3] != sinProps[i + 3];
        if (!cambio) continue;
        tinta++;
        if (x > roadL + 2 && x < roadR - 2) sobreAsfalto++;
      }
    }

    expect(tinta, greaterThan(500), reason: 'los props deben verse en pantalla');
    expect(
      sobreAsfalto,
      0,
      reason: 'ningún prop puede pisar el asfalto',
    );
  });

  test('el tema oscuro apaga el desierto y todo queda opaco', () async {
    final claro = await render(dark: false);
    final oscuro = await render(dark: true);

    for (final px in [claro, oscuro]) {
      var transparentes = 0;
      for (var i = 3; i < px.length; i += 4) {
        if (px[i] != 255) transparentes++;
      }
      expect(transparentes, 0, reason: 'ningún píxel puede quedar sin cubrir');
    }

    double media(Uint8List px) {
      var sum = 0.0;
      for (var i = 0; i < px.length; i += 4) {
        sum += 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
      }
      return sum / (px.length ~/ 4);
    }

    expect(
      media(oscuro),
      lessThan(media(claro)),
      reason: 'la noche debe apagar la escena respecto al día',
    );
  });
}
