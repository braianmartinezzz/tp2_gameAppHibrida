import 'package:flutter/material.dart';

/// Paleta de marca compartida por la UI de Flutter (header, botonera,
/// modales). Los colores de las gemas coinciden con los del corredor para que
/// el diamante se vea igual dentro y fuera del juego.
class AppColors {
  AppColors._();

  // Diamante / gema (mismo cian que las monedas del juego).
  static const Color gem = Color(0xFF46DDF2);
  static const Color gemDeep = Color(0xFF1B9CD8);

  // Dorado: récord, cuenta PRO, medallas.
  static const Color gold = Color(0xFFFFD166);
  static const Color goldDeep = Color(0xFFF59E0B);
  static const Color goldInk = Color(0xFF3B2C00);

  // Botonera: colores "caramelo" con su versión oscura para el borde 3D.
  static const Color play = Color(0xFF34D399);
  static const Color playDeep = Color(0xFF059669);
  static const Color pause = Color(0xFFFFB020);
  static const Color pauseDeep = Color(0xFFC77700);
  static const Color reset = Color(0xFFFF6B8A);
  static const Color resetDeep = Color(0xFFD1365B);
  static const Color mode = Color(0xFF8B7CFF);
  static const Color modeDeep = Color(0xFF5B4BDB);

  // Header: degradé violeta que se lee bien con texto blanco en ambos modos.
  static const List<Color> headerDark = [Color(0xFF3A2E9E), Color(0xFF5B3FD0)];
  static const List<Color> headerLight = [Color(0xFF6C5CE7), Color(0xFF9B6BFF)];
}

/// El juego (canvas de Flame) se mantiene igual en ambos modos,
/// como pide la consigna. Lo que cambia es la UI de Flutter alrededor
/// (header, botonera, modales).
class AppTheme {
  static final ThemeData light = _build(
    brightness: Brightness.light,
    seed: const Color(0xFF6C5CE7),
    background: const Color(0xFFF6F3FF),
  );

  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    seed: const Color(0xFF8B7CFF),
    background: const Color(0xFF14122B),
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color seed,
    required Color background,
  }) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: scheme,
      useMaterial3: true,
      // Botones gorditos y redondeados: pensados para dedos chicos.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
