import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia del progreso (ajustes, billetera, mejoras, desafíos) sobre
/// `shared_preferences`, como un único JSON.
///
/// Está separada de [GameState] para que el estado siga siendo testeable sin
/// plugins: los tests crean `GameState()` sin store y todo queda en memoria.
class SettingsStore {
  static const _key = 'game_save_v1';

  /// `null` si todavía no hay nada guardado (primer arranque).
  Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  /// Borra todo lo guardado: la próxima vez que se abra la app es como una
  /// instalación nueva (`load` devuelve `null`).
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  Future<void> save(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }
}
