import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/coin_component.dart';
import 'package:runner_flutter/game/power_up_component.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';

/// Genera un PNG con las Fases 2 y 3 en escena: patrones de monedas, power-ups
/// flotando, el HUD de poderes en el canvas, el feedback de recolecciones
/// (anillos, chispas y etiquetas) y el corredor en marcha.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('generar preview de gameplay', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 760));

    for (final dark in [true, false]) {
      final gameState = GameState()
        ..lives.value = 1000000 // invulnerable: el preview solo dibuja
        ..themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
      final game = RunnerGame(gameState: gameState, hordeEnabled: false, zombiesEnabled: false);
      await tester.pumpWidget(GameWidget(game: game));

      // Escudo y multiplicador desde el arranque: en el HUD aparecen con sus
      // barras ya avanzadas (el x2 arranca en 8 s y llega a ~6.4 s).
      game.powerUps
        ..apply(PowerUpKind.shield)
        ..apply(PowerUpKind.multiplier);

      // Un patrón de cada familia y un power-up suelto en el corredor.
      game.spawnCoinPattern(
        pattern: CoinPattern.arc,
        anchorLane: -0.5,
        avoidObstacles: false,
      );
      game.spawnCoinPattern(
        pattern: CoinPattern.high,
        anchorLane: 0,
        avoidObstacles: false,
      );
      game.spawnCoinPattern(
        pattern: CoinPattern.zigzag,
        anchorLane: 0.5,
        avoidObstacles: false,
      );
      game.spawnPowerUp(
        kind: PowerUpKind.multiplier,
        lane: 1,
        avoidObstacles: false,
      );

      // ~1.6 s de juego: los patrones avanzan hasta media altura y ya hay
      // obstáculos spawneados, sin que nadie llegue todavía a la fila.
      for (var i = 0; i < 100; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // El imán se activa recién acá (a media duración, para que el HUD
      // muestre sus tres filas): si corriera durante el vuelo jalaría todas
      // las monedas al carril 0 y el preview no mostraría los patrones.
      // Sin pump posterior a propósito: el HUD se dibuja desde el estado y
      // así ninguna moneda se corre ni un carril.
      game.powerUps
        ..apply(PowerUpKind.magnet)
        ..magnetTimer = 4.4;

      // Fase 3: el feedback se dispara a mano y se lo deja ~0.15 s avanzado,
      // para que el preview muestre anillos, chispas y etiquetas en pleno
      // vuelo. Se limpia primero lo que pudo ocurrir durante los pumps
      // (golpes, aterrizajes) y el parpadeo de la invulnerabilidad, para que
      // la imagen salga siempre igual.
      game.juice.reset();
      game.player.blinkAlpha = 1;
      game.juice
        ..coinPickup(const Offset(150, 470))
        ..powerUpPickup(const Offset(330, 440), PowerUpKind.shield)
        ..landDust(
          Offset(game.player.position.x, game.player.groundFeetY),
          blend: dark ? 1.0 : 0.0,
        );
      for (var i = 0; i < 9; i++) {
        game.juice.update(0.016);
      }

      expect(game.children.whereType<CoinComponent>(), isNotEmpty);
      expect(game.children.whereType<PowerUpComponent>(), isNotEmpty);
      expect(game.juice.isIdle, isFalse, reason: 'el feedback queda dibujado');

      // El render a imagen corre fuera de la zona "fake async" de testWidgets,
      // si no el Future de `toImage` nunca se cumple.
      final path = 'build/gameplay_preview_${dark ? 'dark' : 'light'}.png';
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        game.render(canvas); // mapa + componentes + HUD, igual que en pantalla

        final picture = recorder.endRecording();
        final image = await picture.toImage(480, 760);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      debugPrint('guardado: $path');
    }

    // Frame extra: el golpe final de la Fase 3 a media disipación, con la
    // cámara ya corrida (overscan) y la viñeta roja encima.
    final deathState = GameState()..themeMode.value = ThemeMode.dark;
    final deathGame = RunnerGame(gameState: deathState);
    await tester.pumpWidget(GameWidget(game: deathGame));
    await tester.pump(const Duration(milliseconds: 16));
    deathGame.juice.death(
      Offset(deathGame.size.x * 0.5, deathGame.size.y * 0.86),
    );
    for (var i = 0; i < 9; i++) {
      deathGame.juice.update(0.016);
    }
    const deathPath = 'build/gameplay_preview_death.png';
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      deathGame.render(Canvas(recorder));
      final image =
          await recorder.endRecording().toImage(480, 760);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(deathPath).writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    debugPrint('guardado: $deathPath');

    await tester.binding.setSurfaceSize(null);
  });
}
