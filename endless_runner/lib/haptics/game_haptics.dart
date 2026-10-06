import 'package:vibration/vibration.dart';

// El flag es genérico ("¿corro dentro de flutter test?"), vive junto al audio
// porque ahí nació: en los tests no hay plugins de plataforma.
import '../audio/game_music_env_stub.dart'
    if (dart.library.io) '../audio/game_music_env_io.dart';

/// Tipos de golpe táctil que manda el juego. Cada uno tiene una duración
/// distinta para que se pueda distinguir sin mirar la pantalla:
///  - [hit]: el corredor perdió una vida (obstáculo, zombi o camión),
///  - [shield]: el escudo absorbió el impacto (golpe cortito, no cuesta vida),
///  - [death]: última vida o la horda lo alcanzó (vibración más larga).
enum HapticCue { hit, shield, death }

/// Vibración del teléfono (`package:vibration`).
///
/// Es un envoltorio delgado, con la misma filosofía que [GameMusic]:
///  - nada de plugin si [isTestEnvironment] (los tests no vibran y no trapan
///    canales de plataforma que no existen ahí),
///  - todo en `try/catch`: si el aparatito no tiene vibrador (o el sistema
///    bloquea la vibración) el juego sigue corriendo en vez de romperse,
///  - inyectable en `RunnerGame` para que los tests puedan usar un doble y
///    afirmar *qué* cue se disparó sin tocar hardware.
///
/// En Android se apoya en `VibrationEffect` (API 26+) con la duración exacta;
/// en viejos y en iOS el plugin cae a una vibración simple de ~500 ms. El
/// permiso `android.permission.VIBRATE` está en el manifest de la app y en el
/// del plugin.
class GameHaptics {
  /// Duración del golpe que cuesta vida.
  static const Duration hitDuration = Duration(milliseconds: 130);

  /// Duración del impacto que absorbe el escudo (más seco, avisa sin asustar).
  static const Duration shieldDuration = Duration(milliseconds: 80);

  /// Duración de la muerte: la más larga para que se sienta el final.
  static const Duration deathDuration = Duration(milliseconds: 450);

  /// Hace vibrar el teléfono según [cue]. Nunca lanza: si no hay vibrador,
  /// simplemente no vibra.
  Future<void> play(HapticCue cue) async {
    if (isTestEnvironment) return;
    try {
      final milliseconds = switch (cue) {
        HapticCue.hit => hitDuration.inMilliseconds,
        HapticCue.shield => shieldDuration.inMilliseconds,
        HapticCue.death => deathDuration.inMilliseconds,
      };
      await Vibration.vibrate(duration: milliseconds);
    } catch (_) {
      // Sin vibrador o sin permiso: el feedback visual (juice) ya alcanza.
    }
  }
}
