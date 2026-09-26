import 'package:flutter/material.dart';

/// El juego (canvas de Flame) se mantiene igual en ambos modos,
/// como pide la consigna. Lo que cambia es la UI de Flutter alrededor
/// (header, botonera, modales).
class AppTheme {
  static ThemeData light = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF4F1EA),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF3C34D8),
      brightness: Brightness.light,
    ),
    useMaterial3: true,
  );

  static ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF15151A),
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF7F77DD),
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );
}
