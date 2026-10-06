import 'dart:async' show unawaited;

import 'package:audioplayers/audioplayers.dart'
    show
        AssetSource,
        AudioContextConfig,
        AudioContextConfigFocus,
        AudioPlayer,
        PlayerMode,
        ReleaseMode;
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart' show VoidCallback;

import 'game_music_env_stub.dart' if (dart.library.io) 'game_music_env_io.dart';

/// Todos los efectos de sonido del juego. Cada uno trae su archivo, su volumen
/// y cuántas copias pueden sonar a la vez.
///
/// Tres familias, con volúmenes pensados para que se note la jerarquía:
///  - **UI** (botones, diálogos): bips de 8 bits con un "tac" de madera.
///  - **Eventos** (diamantes, power-ups, golpes, muerte, horda): con cuerpo.
///  - **Movimiento** del corredor (pasos, carril, salto, aterrizaje, agachado):
///    ruido suave y grave, a un volumen bastante menor que el resto para que
///    acompañen sin tapar la música ni los avisos.
///
/// Los .wav se generan con `tools/build_sfx.py`.
enum Sfx {
  // --- UI ---
  click('ui_click', 0.70, voices: 2),
  back('ui_back', 0.70),
  play('ui_play', 0.80),
  toggle('ui_toggle', 0.60),
  open('ui_open', 0.55),
  close('ui_close', 0.55),
  pause('ui_pause', 0.65),
  resume('ui_resume', 0.65),
  error('ui_error', 0.60),
  buy('ui_buy', 0.75),
  reward('ui_reward', 0.75),
  success('ui_success', 0.65),

  // --- Eventos del juego ---
  coin('game_coin', 0.55, voices: 3),
  coinBig('game_coin_big', 0.65),
  powerUp('game_powerup', 0.70),
  shield('game_shield', 0.75),
  hit('game_hit', 0.85),
  death('game_death', 0.90),
  revive('game_revive', 0.75),
  hordeAlert('game_horde', 0.60),

  // --- Movimiento del corredor (suave y bajito) ---
  stepA('move_step_a', 0.20),
  stepB('move_step_b', 0.20),
  lane('move_lane', 0.32),
  jump('move_jump', 0.34),
  land('move_land', 0.30),
  roll('move_roll', 0.34);

  const Sfx(this.file, this.volume, {this.voices = 1});

  /// Nombre del archivo (sin extensión) dentro de `assets/audio/sfx/`.
  final String file;

  /// Volumen base (0..1) con el que suena este efecto.
  final double volume;

  /// Cuántas copias del mismo efecto pueden sonar a la vez (pool).
  final int voices;

  /// Ruta relativa al prefijo `assets/audio/` de [FlameAudio].
  String get path => 'sfx/$file.wav';
}

/// Un reproductor ya cargado con su sonido, listo para disparar.
class _Voice {
  _Voice(this.player);

  final AudioPlayer player;

  /// true mientras se está mandando la orden a la plataforma (no mientras
  /// suena): evita apilar órdenes y que se forme una cola de retraso.
  bool busy = false;
}

/// Reproductor de efectos de sonido (singleton).
///
/// Misma filosofía que [GameMusic] y `GameHaptics`:
///  - nada de plugin en los tests ([isTestEnvironment]),
///  - todo en `try/catch`: si la plataforma no puede reproducir, el juego
///    sigue en silencio en vez de romperse,
///  - un interruptor ([enabled]) que decide en un solo lugar si suena algo.
///
/// Cada efecto tiene sus propios [AudioPlayer] en modo `lowLatency`
/// (SoundPool en Android), cargados UNA vez con [preload] y con el volumen ya
/// puesto. Disparar es solo `stop` + `resume`, sin cargar nada, y se reparten
/// en círculo para que el mismo efecto pueda superponerse (p. ej. una línea de
/// diamantes). Si todos los de un efecto están ocupados mandando una orden, el
/// disparo se descarta: es mejor perder un "tic" que acumular retraso.
///
/// (Se evita `AudioPool` en lowLatency: ahí no devuelve el reproductor al pool
/// al terminar el sonido y crea uno nuevo, cargando el asset, en cada disparo.)
///
/// Los efectos usan el prefijo global de [FlameAudio] (`assets/audio/`); la
/// música tiene su propio [AudioCache] con prefijo `assets/`, así que no se
/// pisan.
class GameSfx {
  GameSfx._();

  static final GameSfx instance = GameSfx._();

  /// Lo sincroniza [GameState] con el interruptor de Ajustes.
  bool enabled = true;

  /// Multiplicador general de volumen de todos los efectos.
  double masterVolume = 1.0;

  final Map<Sfx, List<_Voice>> _voices = {};
  final Map<Sfx, Future<void>> _loading = {};
  final Map<Sfx, int> _next = {};
  bool _contextReady = false;

  /// Carga todos los efectos por adelantado (sin esperar al primer toque).
  /// Seguro de llamar varias veces.
  Future<void> preload([Iterable<Sfx> cues = Sfx.values]) async {
    if (isTestEnvironment) return;
    await _prepareContext();
    await Future.wait(cues.map(_load));
  }

  /// Dispara [cue] si los efectos están prendidos. Nunca lanza ni frena el
  /// juego: no se espera la reproducción.
  void play(Sfx cue, {double volume = 1.0}) {
    if (!enabled || isTestEnvironment) return;
    final voices = _voices[cue];
    if (voices == null) {
      // Todavía no cargó: se carga ahora (este disparo se pierde).
      unawaited(_load(cue));
      return;
    }
    final start = _next[cue] ?? 0;
    for (var i = 0; i < voices.length; i++) {
      final voice = voices[(start + i) % voices.length];
      if (voice.busy) continue;
      _next[cue] = (start + i + 1) % voices.length;
      unawaited(_fire(voice));
      return;
    }
    // Todas ocupadas: se descarta.
  }

  Future<void> _fire(_Voice voice) async {
    voice.busy = true;
    try {
      await voice.player.stop();
      await voice.player.resume();
    } catch (_) {
      // Sin audio el juego sigue igual (ver doc de la clase).
    } finally {
      voice.busy = false;
    }
  }

  Future<void> _load(Sfx cue) {
    if (_voices.containsKey(cue)) return Future<void>.value();
    return _loading[cue] ??= _create(cue);
  }

  Future<void> _create(Sfx cue) async {
    try {
      await _prepareContext();
      final created = <_Voice>[];
      for (var i = 0; i < cue.voices; i++) {
        final player = AudioPlayer()..audioCache = FlameAudio.audioCache;
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        await player.setVolume((cue.volume * masterVolume).clamp(0.0, 1.0));
        await player.setSource(AssetSource(cue.path));
        created.add(_Voice(player));
      }
      _voices[cue] = created;
    } catch (_) {
      // Que un fallo no quede guardado: el próximo intento vuelve a probar.
    } finally {
      _loading.remove(cue);
    }
  }

  /// Los efectos tienen que mezclarse con la música: sin esto, en Android cada
  /// efecto pide el foco de audio y la canción de la partida se corta o baja.
  Future<void> _prepareContext() async {
    if (_contextReady) return;
    _contextReady = true;
    try {
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
    } catch (_) {}
  }

  /// Corta lo que esté sonando (al salir de la partida al menú).
  void stopAll() {
    if (isTestEnvironment) return;
    for (final voices in _voices.values) {
      for (final voice in voices) {
        unawaited(voice.player.stop().catchError((Object _) {}));
      }
    }
  }

  /// Libera todos los reproductores (no hace falta en el uso normal de la app).
  Future<void> dispose() async {
    final all = _voices.values.expand((v) => v).toList();
    _voices.clear();
    for (final voice in all) {
      try {
        await voice.player.dispose();
      } catch (_) {}
    }
  }
}

/// Envuelve un callback de botón para que suene [sfx] al tocarlo.
///
/// Devuelve `null` si [onTap] es `null`, así los botones deshabilitados siguen
/// deshabilitados y callados:
/// ```dart
/// FilledButton(onPressed: sfxTap(onRestart), ...)
/// ```
VoidCallback? sfxTap(VoidCallback? onTap, {Sfx sfx = Sfx.click}) {
  if (onTap == null) return null;
  return () {
    GameSfx.instance.play(sfx);
    onTap();
  };
}

/// Igual que [sfxTap] pero para destinos que exigen un callback no nulo (p. ej.
/// un botón propio con `required VoidCallback onPressed`).
VoidCallback sfxCallback(VoidCallback onTap, {Sfx sfx = Sfx.click}) {
  return () {
    GameSfx.instance.play(sfx);
    onTap();
  };
}
