import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runner_flutter/game/map_renderer.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/settings_store.dart';
import 'package:runner_flutter/theme/app_theme.dart';

/// Los componentes `red` / `green` / `blue` de `Color` están deprecados:
/// el byte 0..255 se saca del doble normalizado.
int ch8(double v) {
  final x = (v * 255).round();
  return x < 0 ? 0 : (x > 255 ? 255 : x);
}

/// Tema claro/oscuro de punta a punta: el ciclo del botón, la resolución del
/// modo "Auto" contra el sistema, la persistencia, el fundido del desierto y
/// el contraste de la UI.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ciclo del botón 🌓', () {
    test('recorre Auto → Claro → Oscuro → Auto', () {
      final state = GameState()..themeMode.value = ThemeMode.system;

      state.cycleTheme();
      expect(state.themeMode.value, ThemeMode.light);
      state.cycleTheme();
      expect(state.themeMode.value, ThemeMode.dark);
      state.cycleTheme();
      expect(state.themeMode.value, ThemeMode.system);
    });

    test('por defecto el tema es Auto (sigue al sistema)', () {
      expect(GameState().themeMode.value, ThemeMode.system);
    });
  });

  group('modo efectivo (Auto)', () {
    test('system se resuelve contra el brillo del sistema', () {
      final state = GameState()..themeMode.value = ThemeMode.system;

      state.platformBrightness.value = Brightness.dark;
      expect(state.isDark, isTrue);
      expect(state.effectiveBrightness, Brightness.dark);

      state.platformBrightness.value = Brightness.light;
      expect(state.isDark, isFalse);
      expect(state.effectiveBrightness, Brightness.light);
    });

    test('un tema fijo ignora el brillo del sistema', () {
      final state = GameState();

      state.themeMode.value = ThemeMode.dark;
      state.platformBrightness.value = Brightness.light;
      expect(state.isDark, isTrue);

      state.themeMode.value = ThemeMode.light;
      state.platformBrightness.value = Brightness.dark;
      expect(state.isDark, isFalse);
    });
  });

  group('persistencia', () {
    test('el tema elegido se guarda y se recupera', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore();

      final first = GameState(store: store)..themeMode.value = ThemeMode.light;
      expect(first.toJson()['theme'], 'light');
      first.save();
      await pumpEventQueue();

      final second = GameState(store: store);
      await second.loadSettings();
      expect(second.themeMode.value, ThemeMode.light);
    });

    test('un guardado viejo sin tema deja el default Auto', () async {
      SharedPreferences.setMockInitialValues({
        'game_save_v1': '{"tutorialSeen":true,"swipeSensitivity":1.5}',
      });

      final state = GameState(store: SettingsStore());
      await state.loadSettings();

      expect(state.themeMode.value, ThemeMode.system);
      // El resto del save sí se carga: la clave nueva es opcional.
      expect(state.tutorialSeen.value, isTrue);
      expect(state.swipeSensitivity.value, 1.5);
    });
  });

  group('fundido en el juego', () {
    test('nace en el modo efectivo', () {
      final state = GameState()..themeMode.value = ThemeMode.light;
      final game = RunnerGame(gameState: state);
      expect(game.themeBlend, 0);

      final night = RunnerGame(
        gameState: GameState()..themeMode.value = ThemeMode.dark,
      );
      expect(night.themeBlend, 1);
    });

    test('con el motor corriendo el blend camina hasta el objetivo', () {
      final state = GameState()..themeMode.value = ThemeMode.light;
      final game = RunnerGame(gameState: state);
      expect(game.themeBlend, 0);

      state.themeMode.value = ThemeMode.dark;
      // update() anima; un solo frame no llega al final.
      game.advanceThemeFade(0.1);
      expect(game.themeBlend, greaterThan(0));
      expect(game.themeBlend, lessThan(1));

      for (var i = 0; i < 30; i++) {
        game.advanceThemeFade(0.1);
      }
      expect(game.themeBlend, 1);
    });

    test('con el motor pausado se clava en el objetivo', () {
      final state = GameState()..themeMode.value = ThemeMode.dark;
      final game = RunnerGame(gameState: state);
      expect(game.themeBlend, 1);

      game.pauseEngine();
      state.themeMode.value = ThemeMode.light;
      expect(game.themeBlend, 0);

      // También cuando el cambio viene del sistema (modo Auto).
      state.platformBrightness.value = Brightness.dark;
      state.themeMode.value = ThemeMode.system;
      expect(game.themeBlend, 1);

      state.platformBrightness.value = Brightness.light;
      expect(game.themeBlend, 0);
    });
  });

  group('desierto día ↔ noche', () {
    const w = 120;
    const h = 200;
    const p = Perspective(width: 120, height: 200);

    /// Color promedio de un bloque del asfalto cercano: no hay estrellas,
    /// luna ni sol en esa zona, así que lo único que cambia es la paleta.
    Future<Color> roadColor(double blend) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final map = MapRenderer()..drawProps = false;
      for (var i = 0; i < 5; i++) {
        map.update(1 / 60, 300, p);
      }
      map.render(canvas, p, blend: blend, playerX: w * 0.5);

      final image = await recorder.endRecording().toImage(w, h);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final px = bytes!.buffer.asUint8List();

      var r = 0, g = 0, b = 0, n = 0;
      for (var y = h - 8; y < h - 4; y++) {
        for (var x = 4; x < 12; x++) {
          final i = (y * w + x) * 4;
          r += px[i];
          g += px[i + 1];
          b += px[i + 2];
          n++;
        }
      }
      return Color.fromRGBO(r ~/ n, g ~/ n, b ~/ n, 1);
    }

    test('los extremos son claramente distintos', () async {
      final day = await roadColor(0);
      final night = await roadColor(1);

      final diff = (ch8(day.r) - ch8(night.r)).abs() +
          (ch8(day.g) - ch8(night.g)).abs() +
          (ch8(day.b) - ch8(night.b)).abs();
      expect(diff, greaterThan(30),
          reason: 'día y noche son paletas distintas');
    });

    test('a mitad de camino el color queda entre los dos extremos', () async {
      final day = await roadColor(0);
      final night = await roadColor(1);
      final mid = await roadColor(0.5);

      for (final ch in [
        (ch8(day.r), ch8(night.r), ch8(mid.r)),
        (ch8(day.g), ch8(night.g), ch8(mid.g)),
        (ch8(day.b), ch8(night.b), ch8(mid.b)),
      ]) {
        final lo = min(ch.$1, ch.$2) - 4;
        final hi = max(ch.$1, ch.$2) + 4;
        expect(
          ch.$3,
          inInclusiveRange(lo, hi),
          reason: 'el blend intermedio no se pasa de un extremo al otro',
        );
      }
    });
  });

  group('contraste de la UI', () {
    double luminance(Color c) {
      double channel(int v) {
        final s = v / 255;
        if (s <= 0.04045) return s / 12.92;
        return pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * channel(ch8(c.r)) +
          0.7152 * channel(ch8(c.g)) +
          0.0722 * channel(ch8(c.b));
    }

    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
    }

    for (final (name, theme) in [
      ('claro', AppTheme.light),
      ('oscuro', AppTheme.dark),
    ]) {
      test('texto sobre superficies ($name) ≥ 4.5:1', () {
        final scheme = theme.colorScheme;
        expect(
          contrast(scheme.onSurface, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5),
          reason: 'texto de la pantalla principal sobre el fondo',
        );
        expect(
          contrast(scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
          greaterThanOrEqualTo(4.5),
          reason: 'rótulos de la botonera y de los modales',
        );
        expect(
          contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
          reason: 'botones rellenos',
        );
      });
    }

    test('el oro del récord soporta su tinta', () {
      expect(
        contrast(AppColors.goldInk, AppColors.gold),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('el blanco del header se lee sobre los dos degradés', () {
      // Los rótulos del header son negrita grande (títulos y contadores):
      // el umbral AA para texto grande es 3:1.
      for (final stops in [AppColors.headerLight, AppColors.headerDark]) {
        for (final stop in stops) {
          expect(
            contrast(Colors.white, stop),
            greaterThanOrEqualTo(3.0),
            reason: 'blanco sobre ${stop.toARGB32().toRadixString(16)}',
          );
        }
      }
    });
  });
}
