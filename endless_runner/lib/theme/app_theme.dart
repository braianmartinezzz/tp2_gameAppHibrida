import 'package:flutter/material.dart';

/// Paleta de marca compartida por la UI de Flutter (header, botonera,
/// modales): "ceniza y brasa". Base marrón/carbón cálida (como el desierto
/// del juego y los paneles pixel de la pantalla de inicio) y naranja brasa
/// solo como acento en lo principal. Los colores de las gemas coinciden con
/// los del corredor para que el diamante se vea igual dentro y fuera del
/// juego.
class AppColors {
  AppColors._();

  // Diamante / gema (mismo cian que las monedas del juego).
  static const Color gem = Color(0xFF46DDF2);
  static const Color gemDeep = Color(0xFF1B9CD8);

  // Dorado: récord, cuenta PRO, medallas.
  static const Color gold = Color(0xFFFFD166);
  static const Color goldDeep = Color(0xFFF59E0B);
  static const Color goldInk = Color(0xFF3B2C00);

  // Marca: naranja brasa (acento), tinta oscura y crema.
  static const Color ember = Color(0xFFF08A0C);
  static const Color emberDeep = Color(0xFFB54708);
  static const Color ink = Color(0xFF140E0C);
  static const Color cream = Color(0xFFF3E6CF);

  // Colores con significado (éxito, aviso, error) que usan los modales.
  static const Color play = Color(0xFF34D399);
  static const Color playDeep = Color(0xFF059669);
  static const Color pause = Color(0xFFFFB020);
  static const Color pauseDeep = Color(0xFFC77700);
  static const Color reset = Color(0xFFFF6B8A);
  static const Color resetDeep = Color(0xFFD1365B);

  // Botonera tipo consola: colores claros con el ícono en tinta oscura
  // (contraste ≥ 4.5:1). Jugar es el principal, por eso lleva el naranja.
  static const Color ctrlPlay = Color(0xFFF08A0C);
  static const Color ctrlPlayDeep = Color(0xFFB35F00);
  static const Color ctrlPause = Color(0xFFE9D5A8);
  static const Color ctrlPauseDeep = Color(0xFFB9A27A);
  static const Color ctrlReset = Color(0xFFE8594A);
  static const Color ctrlResetDeep = Color(0xFFA8362B);

  // Botón de modo: azul noche, el único frío de la botonera para que se
  // distinga de los demás.
  static const Color mode = Color(0xFF6C8FE0);
  static const Color modeDeep = Color(0xFF3F5FAE);

  // Header: panel marrón oscuro (más cálido en el modo claro) con texto
  // crema/blanco; contraste ≥ 4.5:1 en los dos extremos.
  static const List<Color> headerDark = [Color(0xFF2A2322), Color(0xFF181314)];
  static const List<Color> headerLight = [Color(0xFF5A3A24), Color(0xFF3B2416)];
}

/// El juego (canvas de Flame) también cambia: el desierto es de día con el
/// tema claro y nocturno (estrellado) con el oscuro, con un fundido de
/// ~0.35 s entre ambos. Lo que cambia además es la UI de Flutter alrededor
/// (header, botonera, modales) y la barra de estado. El violeta quedó solo
/// en el cielo de la noche del mapa.
class AppTheme {
  static final ThemeData light = _build(
    brightness: Brightness.light,
    scheme: const ColorScheme.light(
      primary: Color(0xFFB54708),
      onPrimary: Color(0xFFFFFFFF),
      secondary: Color(0xFF8A5A2B),
      onSecondary: Color(0xFFFFFFFF),
      tertiary: Color(0xFF8A5A00),
      onTertiary: Color(0xFFFFFFFF),
      surface: Color(0xFFFBF3E3),
      onSurface: Color(0xFF2A1D14),
      onSurfaceVariant: Color(0xFF5A4636),
      outline: Color(0xFF8A7560),
      outlineVariant: Color(0xFFCDB68E),
      surfaceContainerLowest: Color(0xFFFFF9EC),
      surfaceContainerLow: Color(0xFFF8EEDA),
      surfaceContainer: Color(0xFFF2E4C9),
      surfaceContainerHigh: Color(0xFFEBD9B9),
      surfaceContainerHighest: Color(0xFFE6D2B0),
    ),
    background: const Color(0xFFF5E9D3),
  );

  static final ThemeData dark = _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme.dark(
      primary: Color(0xFFF08A0C),
      onPrimary: Color(0xFF2A140A),
      secondary: Color(0xFFD9B777),
      onSecondary: Color(0xFF2A1D14),
      tertiary: Color(0xFFFFD166),
      onTertiary: Color(0xFF3B2C00),
      surface: Color(0xFF241C19),
      onSurface: Color(0xFFF3E6CF),
      onSurfaceVariant: Color(0xFFD9C7AE),
      outline: Color(0xFF7A6B5E),
      outlineVariant: Color(0xFF4A3F3A),
      surfaceContainerLowest: Color(0xFF140E0C),
      surfaceContainerLow: Color(0xFF2A211D),
      surfaceContainer: Color(0xFF2D231E),
      surfaceContainerHigh: Color(0xFF30261F),
      surfaceContainerHighest: Color(0xFF33281F),
    ),
    background: const Color(0xFF181210),
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
  }) {
    // `surfaceTint` en transparente: Material 3 tiñe cada nivel de elevación
    // con el color primario y dejaba un halo extraño bajo las tarjetas y los
    // diálogos.
    final colors = scheme.copyWith(surfaceTint: Colors.transparent);
    // Esquinas chicas: más cerca de los paneles pixel que de los "caramelos".
    const sheetShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: background,
      colorScheme: colors,
      useMaterial3: true,
      // Hojas inferiores (premios, tienda): mismas esquinas que los diálogos
      // y sin tinte de elevación.
      bottomSheetTheme: const BottomSheetThemeData(
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: sheetShape,
      ),
      dialogTheme: const DialogThemeData(
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      // Slider de sensibilidad: pulgares grandes y pistas gruesas.
      sliderTheme: const SliderThemeData(
        trackHeight: 6,
        thumbShape: RoundSliderThumbShape(enabledThumbRadius: 9),
        overlayShape: RoundSliderOverlayShape(overlayRadius: 18),
      ),
      // Botones gorditos: pensados para dedos chicos.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: buttonShape,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.inverseSurface,
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: colors.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
