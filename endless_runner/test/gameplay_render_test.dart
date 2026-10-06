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

/// Renderiza el juego **tal como está en este frame** y devuelve los bytes
/// RGBA. Si se pasa [hide], esas recompensas se achican a 0 (dejan de dibujar)
/// sin mover nada: el diff entre dos renders es exactamente lo que aporta esa
/// recompensa, sin depender del color ni del tema.
Future<Uint8List> _renderRgba(RunnerGame game, {Set<Object>? hide}) async {
  void shrink(Iterable<Object> items) {
    for (final item in items) {
      if (item is CoinComponent) {
        item.size.setValues(0, 0);
      } else if (item is PowerUpComponent) {
        item.size.setValues(0, 0);
      }
    }
  }

  shrink(hide ?? const []);
  final recorder = ui.PictureRecorder();
  game.render(Canvas(recorder));
  final image = await recorder.endRecording().toImage(_w, _h);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  // Restaura la geometría real de todo lo que se achicó.
  for (final coin in game.children.whereType<CoinComponent>()) {
    coin.syncGeometry();
  }
  for (final item in game.children.whereType<PowerUpComponent>()) {
    item.syncGeometry();
  }
  return bytes!.buffer.asUint8List();
}

/// Píxeles distintos entre [a] y [b] dentro del rectángulo pedido.
int _diffIn(Uint8List a, Uint8List b, double x, double y, double w, double h) {
  final x0 = x.floor().clamp(0, _w - 1);
  final y0 = y.floor().clamp(0, _h - 1);
  final x1 = (x + w).ceil().clamp(0, _w);
  final y1 = (y + h).ceil().clamp(0, _h);
  var n = 0;
  for (var py = y0; py < y1; py++) {
    for (var px = x0; px < x1; px++) {
      final i = (py * _w + px) * 4;
      if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) n++;
    }
  }
  return n;
}

/// Píxeles transparentes del borde del lienzo: si el mapa no cubre todo, el
/// temblor dejaría el fondo de la app asomando.
int _transparentBorder(Uint8List rgba) {
  var n = 0;
  for (var x = 0; x < _w; x++) {
    if (rgba[x * 4 + 3] < 8) n++; // fila de arriba
    if (rgba[((_h - 1) * _w + x) * 4 + 3] < 8) n++; // fila de abajo
  }
  for (var y = 0; y < _h; y++) {
    if (rgba[y * _w * 4 + 3] < 8) n++; // columna izquierda
    if (rgba[(y * _w + _w - 1) * 4 + 3] < 8) n++; // columna derecha
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cada moneda y power-up aporta píxeles en su propia caja',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 760));
    final gameState = GameState()
      ..lives.value = 1000000 // invulnerable: acá solo se mide el dibujo
      ..themeMode.value = ThemeMode.dark;
    final game = RunnerGame(gameState: gameState, hordeEnabled: false, zombiesEnabled: false, trucksEnabled: false);
    await tester.pumpWidget(GameWidget(game: game));

    // Los tres patrones más representativos, cada uno en su zona del corredor.
    final coins = <CoinComponent>[
      ...game.spawnCoinPattern(
        pattern: CoinPattern.arc,
        anchorLane: -0.5,
        avoidObstacles: false,
      ),
      ...game.spawnCoinPattern(
        pattern: CoinPattern.high,
        anchorLane: 0,
        avoidObstacles: false,
      ),
      ...game.spawnCoinPattern(
        pattern: CoinPattern.zigzag,
        anchorLane: 0.5,
        avoidObstacles: false,
      ),
    ];
    final spawnedItem = game.spawnPowerUp(
      kind: PowerUpKind.multiplier,
      lane: 1,
      avoidObstacles: false,
    );
    expect(spawnedItem, isNotNull);
    final item = spawnedItem!;

    // ~1.6 s: los patrones avanzan hasta media altura, ya opacos.
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      game.children.whereType<CoinComponent>(),
      hasLength(coins.length),
      reason: 'las 22 monedas siguen en el árbol (no se dibujan fuera de la '
          'pantalla ni se recogen a mitad de vuelo)',
    );

    late Uint8List visible;
    late Uint8List withoutCoins;
    late Uint8List withoutItem;
    await tester.runAsync(() async {
      visible = await _renderRgba(game);
      withoutCoins = await _renderRgba(game, hide: coins.toSet());
      withoutItem = await _renderRgba(game, hide: {item});
    });

    // 1) Cada moneda individualmente: si desaparece del dibujo, su caja no
    //    cambia ni un píxel.
    for (final coin in coins) {
      final n = _diffIn(
        visible,
        withoutCoins,
        coin.position.x,
        coin.position.y,
        coin.size.x,
        coin.size.y,
      );
      expect(
        n,
        greaterThan(0),
        reason: 'la moneda (lane=${coin.lane}, '
            't=${coin.t.toStringAsFixed(2)}) no se dibuja en '
            '(${coin.position.x.toStringAsFixed(0)}, '
            '${coin.position.y.toStringAsFixed(0)})',
      );
    }

    // 2) Cobertura por zonas: el arco cae a la izquierda, la nube y el zigzag
    //    en el centro, y el bloque derecho del zigzag en la calle derecha.
    const bands = <(String, int, int)>[
      ('izquierda (arco)', 90, 225),
      ('centro (nube + zigzag)', 225, 265),
      ('derecha (zigzag carril 1)', 300, 460),
    ];
    for (final (label, from, to) in bands) {
      final n = _diffIn(visible, withoutCoins, from.toDouble(), 0,
          (to - from).toDouble(), _h.toDouble());
      expect(
        n,
        greaterThan(20),
        reason: 'la zona $label quedó vacía de monedas',
      );
    }

    // 3) El power-up suelto también se dibuja donde dice su caja.
    final itemDiff = _diffIn(
      visible,
      withoutItem,
      item.position.x,
      item.position.y,
      item.size.x,
      item.size.y,
    );
    expect(itemDiff, greaterThan(0), reason: 'el power-up no se dibuja');

    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('con la cámara al máximo el temblor no descubre el borde',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 760));
    final gameState = GameState()
      ..lives.value = 1000000
      ..themeMode.value = ThemeMode.dark;
    final game = RunnerGame(gameState: gameState, hordeEnabled: false, zombiesEnabled: false, trucksEnabled: false);
    await tester.pumpWidget(GameWidget(game: game));
    for (var i = 0; i < 30; i++) {
      game.powerUps.grantInvulnerability(); // sin golpes: aísla la sacudida
      await tester.pump(const Duration(milliseconds: 16));
    }

    late Uint8List calm;
    late Uint8List shaken;
    await tester.runAsync(() async {
      calm = await _renderRgba(game);
      game.juice.addShake(Juice.maxShake);
      shaken = await _renderRgba(game);
    });

    expect(
      _transparentBorder(calm),
      0,
      reason: 'premisa: el mapa cubre el lienzo entero',
    );
    expect(
      _transparentBorder(shaken),
      0,
      reason: 'el overscan evita que el borde se descubra al temblar',
    );
    await tester.binding.setSurfaceSize(null);
  });
}
