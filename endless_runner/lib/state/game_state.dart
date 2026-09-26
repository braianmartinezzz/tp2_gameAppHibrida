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

  bool get isPro => accountType.value == 'pro';

  void addScore(int points) => score.value += points;

  void addDiamonds(int amount) => diamonds.value += amount;

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
    isGameOver.value = false;
  }
}
