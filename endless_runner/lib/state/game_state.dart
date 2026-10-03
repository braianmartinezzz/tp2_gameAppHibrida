import 'package:flutter/material.dart';

/// Estado global simulado del jugador y de la partida.
/// Se pasa por referencia al FlameGame para que el juego pueda
/// leer/escribir score y diamantes, y la UI de Flutter (header,
/// botonera, modales) reaccione a los cambios sin acoplarse al motor.
class GameState {
  final ValueNotifier<String> username = ValueNotifier('braian_123');
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> diamonds = ValueNotifier(85);
  final ValueNotifier<String> accountType = ValueNotifier('basic'); // 'basic' | 'pro'
  final ValueNotifier<bool> isGameOver = ValueNotifier(false);
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);

  /// Mejor puntaje de la sesión. Vive en memoria (como todo el estado
  /// simulado de este prototipo): sobrevive a los reinicios de partida, no a
  /// cerrar la app.
  final ValueNotifier<int> bestScore = ValueNotifier(0);

  /// true si la partida que acaba de terminar superó el récord anterior.
  final ValueNotifier<bool> isNewRecord = ValueNotifier(false);

  /// Diamantes ganados en la partida actual (distinto de [diamonds], que es
  /// la billetera: se puede gastar en la tienda o en los golpes).
  final ValueNotifier<int> runDiamonds = ValueNotifier(0);

  bool get isPro => accountType.value == 'pro';

  void addScore(int points) => score.value += points;

  void addDiamonds(int amount) => diamonds.value += amount;

  /// Diamante recolectado en el corredor: suma a la billetera y al resumen de
  /// la partida, para que el game over pueda contar lo ganado en la corrida.
  void collectDiamond() {
    diamonds.value += 1;
    runDiamonds.value += 1;
  }

  /// Termina la partida: congela el resultado y actualiza el récord.
  ///
  /// Es la única puerta de entrada a [isGameOver]: así el resumen nunca ve un
  /// récord desactualizado, y un segundo llamado (colisión doble, test raro)
  /// no pisa lo que ya se celebró.
  void finishRun() {
    if (isGameOver.value) return;
    isNewRecord.value = score.value > bestScore.value;
    if (isNewRecord.value) bestScore.value = score.value;
    isGameOver.value = true;
  }

  /// Devuelve true si pudo pagar (simulado, nunca falla en este prototipo).
  bool spendDiamonds(int amount) {
    if (diamonds.value < amount) return false;
    diamonds.value -= amount;
    return true;
  }

  void toggleAccountType() {
    accountType.value = isPro ? 'basic' : 'pro';
  }

  void toggleTheme() {
    themeMode.value =
        themeMode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void resetRun() {
    score.value = 0;
    runDiamonds.value = 0;
    isNewRecord.value = false;
    isGameOver.value = false;
    // bestScore NO se toca: el récord es lo único que sobrevive a un reinicio.
  }
}
