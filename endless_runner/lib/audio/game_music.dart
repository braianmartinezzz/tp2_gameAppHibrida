import 'package:flame_audio/bgm.dart';
import 'package:flame_audio/flame_audio.dart';

import 'game_music_env_stub.dart' if (dart.library.io) 'game_music_env_io.dart';

/// Música de la partida: `assets/music/powerup.mp3`, en loop mientras el
/// corredor está corriendo.
///
/// Es un envoltorio delgado sobre [Bgm] de flame_audio con cuatro acciones:
///  - [start]: arranca el tema **desde el principio** (partida nueva),
///  - [pause]: lo corta guardando el punto (pausa del juego o muerte),
///  - [resume]: lo sigue desde donde estaba (reanudar, revivir, toggle ON),
///  - [dispose]: lo corta y libera el player (al volver al menú).
///
/// Dos detalles:
///  - flame_audio busca los audios bajo `assets/audio/` (su prefijo default) y
///    este juego los guarda en `assets/`, por eso el [Bgm] se crea con
///    [assetPrefix]. Así no se toca el prefijo global que usarían los efectos
///    de sonido.
///  - Todo lo que toca el plugin va en try/catch: si la plataforma no puede
///    reproducir, el juego sigue sin música en vez de romperse. Y en los tests
///    no hay plugin, así que [isTestEnvironment] apaga la clase por completo.
class GameMusic {
  /// Ruta de la pista relativa a [assetPrefix].
  static const String track = 'music/powerup.mp3';

  /// Carpeta de assets del proyecto (la música vive en `assets/music/`).
  static const String assetPrefix = 'assets/';

  /// Se crea en el primer sonido: así un juego que nunca reproduce (p. ej. un
  /// test) no instancia ningún player de audio.
  Bgm? _bgm;

  /// true cuando la pista ya cargó: dice si [resume] tiene algo que reanudar
  /// o si todavía hay que arrancarla con [start].
  bool _started = false;

  /// Canción en loop desde el principio.
  Future<void> start() async {
    if (isTestEnvironment) return;
    try {
      final bgm = _ensure();
      await bgm.initialize();
      await bgm.play(track);
      _started = true;
    } catch (_) {
      // Sin audio el juego sigue igual (ver doc de la clase).
    }
  }

  /// Corta la música sin perder el punto donde iba.
  Future<void> pause() async {
    if (isTestEnvironment || !_started) return;
    try {
      await _ensure().pause();
    } catch (_) {}
  }

  /// Sigue desde donde estaba. Si nunca sonó, la arranca desde cero.
  Future<void> resume() async {
    if (isTestEnvironment) return;
    if (!_started) {
      await start();
      return;
    }
    try {
      await _ensure().resume();
    } catch (_) {}
  }

  /// Corta la música y libera el player (al salir de la pantalla de juego).
  Future<void> dispose() async {
    final bgm = _bgm;
    _bgm = null;
    _started = false;
    if (bgm == null) return;
    try {
      await bgm.dispose();
    } catch (_) {}
  }

  Bgm _ensure() => _bgm ??= Bgm(audioCache: AudioCache(prefix: assetPrefix));
}
