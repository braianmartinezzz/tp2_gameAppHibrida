import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../audio/game_music.dart';
import '../state/game_state.dart';
import '../state/rewards.dart';
import 'chase_horde.dart';
import 'coin_component.dart';
import 'depth_component.dart';
import 'juice.dart';
import 'map_renderer.dart';
import 'player_component.dart';
import 'obstacle_component.dart';
import 'perspective.dart';
import 'power_up_component.dart';
import 'power_up_state.dart';
import 'speed_rumble.dart';
import 'zombie_obstacle.dart';

/// Acciones que el jugador dispara con un gesto. El tutorial las escucha para
/// saber si el usuario hizo lo que se le pidió.
enum RunnerAction { moveLeft, moveRight, jump, roll }

class RunnerGame extends FlameGame with PanDetector, HasCollisionDetection {
  RunnerGame({
    required this.gameState,
    this.hordeEnabled = true,
    this.zombiesEnabled = true,
    GameMusic? music,
  }) : music = music ?? GameMusic() {
    // El tema se escucha desde el minuto cero (no recién cuando el motor
    // arranca) y el fundido nace en el modo efectivo: así la primera vez que
    // se dibuja el desierto ya sale con el día o la noche que corresponde.
    _listenTheme();
    _themeBlend = _themeTarget;
  }

  final GameState gameState;

  /// Fundido entre el desierto de día (0) y el nocturno (1).
  ///
  /// El cambio de tema no corta en seco: [advanceThemeFade] lo anima durante
  /// [_themeFadeSeconds] y el mapa mezcla las dos paletas con ese valor.
  double _themeBlend = 1;

  /// true mientras los oyentes del tema están enganchados (para no duplicarlos
  /// si el juego se vuelve a montar).
  bool _listeningTheme = false;

  /// Duración del fundido al alternar el tema, en segundos.
  static const double _themeFadeSeconds = 0.35;

  /// Blend actual del tema, expuesto para tests y previews.
  double get themeBlend => _themeBlend;

  /// Horda de zombies que persigue al corredor desde atrás: si lo alcanza, es
  /// Game Over. Los tests que miden otra cosa (spawn, dibujo de recompensas)
  /// la apagan para que el corredor sin input no muera por la horda.
  bool hordeEnabled;

  /// Estado de la horda (expuesto para tests y previews).
  final ChaseHorde horde = ChaseHorde();

  /// Zombis móviles que aparecen como obstáculos (patrullan o persiguen al
  /// jugador). Los tests que miden otra cosa los apagan.
  bool zombiesEnabled;

  /// Se llama cada vez que un gesto produce una acción efectiva del corredor
  /// (un salto en el aire, que no hace nada, no cuenta).
  void Function(RunnerAction action)? onAction;

  /// Modo tutorial: el piso corre y el corredor responde a los gestos, pero no
  /// hay obstáculos, monedas, score ni colisiones. Así el usuario practica sin
  /// riesgo y ve el efecto real de cada gesto.
  bool tutorialActive = false;

  /// true si se puede pausar ahora (no hay partida terminada, ni tutorial, ni
  /// pausa previa).
  bool get canPause =>
      !gameState.isGameOver.value &&
      !gameState.isPaused.value &&
      !tutorialActive;

  /// Pausa la partida y avisa a la UI (overlay de pausa) vía [GameState].
  /// Al ponerse `isPaused` los oyentes de [_syncMusic] cortan la música.
  void pauseGame() {
    if (!canPause) return;
    gameState.isPaused.value = true;
    gameState.save(); // la pausa es buen momento para persistir lo recolectado
    pauseEngine();
  }

  /// Reanuda una partida pausada con [pauseGame]: los oyentes de [_syncMusic]
  /// vuelven a poner la música desde donde se cortó.
  void resumeGame() {
    if (!gameState.isPaused.value) return;
    gameState.isPaused.value = false;
    resumeEngine();
  }

  // --- Música ----------------------------------------------------------------

  /// Música de la partida (`assets/music/powerup.mp3`). Arranca cuando el
  /// corredor sale a correr y sigue el ciclo de vida del juego: pausa,
  /// muerte, revivir, reinicio, interruptor de Ajustes y vuelta al menú.
  /// Se puede inyectar (tests) para escuchar qué manda el juego a hacer.
  final GameMusic music;

  /// true mientras se enganchan los oyentes de [music] (para no duplicarlos
  /// si el juego se vuelve a montar).
  bool _listeningMusic = false;

  /// true mientras [restartRun] limpia la corrida: los oyentes que saltan al
  /// resetear el estado no tocan la música, porque el arranque de la partida
  /// nueva la manda a empezar desde cero al final.
  bool _restartingRun = false;

  void _listenMusic() {
    if (_listeningMusic) return;
    _listeningMusic = true;
    gameState.isGameOver.addListener(_syncMusic);
    gameState.isPaused.addListener(_syncMusic);
    gameState.musicEnabled.addListener(_syncMusic);
  }

  void _unlistenMusic() {
    if (!_listeningMusic) return;
    _listeningMusic = false;
    gameState.isGameOver.removeListener(_syncMusic);
    gameState.isPaused.removeListener(_syncMusic);
    gameState.musicEnabled.removeListener(_syncMusic);
  }

  /// Ajusta la música al estado de la partida: sonando mientras hay corrida
  /// viva y sin pausa, cortada al morir, al pausar o si el jugador la apagó
  /// en Ajustes. Cortar usa [GameMusic.pause] (guarda el punto) para que
  /// revivir o reanudar la siga donde estaba.
  void _syncMusic() {
    if (_restartingRun) return;
    final playing = gameState.musicEnabled.value &&
        !gameState.isGameOver.value &&
        !gameState.isPaused.value;
    if (playing) {
      music.resume();
    } else {
      music.pause();
    }
  }

  late PlayerComponent _player;
  bool _hasPlayer = false;

  /// Jugador vivo (expuesto para tests).
  PlayerComponent get player => _player;

  /// Power-ups activos (escudo / imán / x2): estado puro, fuera del árbol de
  /// componentes. El HUD lo dibuja y los tests lo leen.
  final PowerUpState powerUps = PowerUpState();

  /// Feedback instantáneo (Fase 3): chispas, anillos, etiquetas, destello y
  /// sacudida. Es público como [powerUps] para que tests y previews puedan
  /// dispararlo a mano y medirlo.
  final Juice juice = Juice();

  /// true mientras el jugador estuvo en el aire en el frame anterior (para el
  /// polvo del aterrizaje).
  bool _wasAirborne = false;

  /// Segundos que sigue animándose el feedback tras el golpe final antes de
  /// pausar el motor. Si se pausara de entrada, el destello de la muerte se
  /// congelaría a plena opacidad y la cámara quedaría corrida: el mundo está
  /// congelado igual (ver [update]), solo se disipa el juice.
  static const double _deathGrace = 1.05;
  double _deathTimer = 0;

  final List<ObstacleComponent> _obstacles = [];
  final List<ZombieObstacle> _zombies = [];
  final List<CoinComponent> _coins = [];
  final List<PowerUpComponent> _powerUpItems = [];
  final Random _rng = Random();
  final MapRenderer _map = MapRenderer();

  double _spawnCooldown = 0;

  // Zombis: primer zombi a los 3 s; después la cadencia sube con la dificultad.
  double _zombieCooldown = _firstZombieDelay;
  static const double _firstZombieDelay = 3.0;

  /// true cuando ya toca un zombi pero todavía hay un obstáculo muy fresco:
  /// el spawner de obstáculos se frena hasta que el zombi pueda nacer. Sin
  /// esto, apenas los obstáculos nacen más seguido que [_zombieClearance]
  /// (a partir de ~10 s de partida) los zombis quedaban esperando para
  /// siempre y no volvían a aparecer.
  bool _zombieDue = false;

  /// Zombis generados en la partida y últimos tipos: sirven para que los tres
  /// tipos se vean desde el principio y no se repita el mismo muchas veces.
  int _zombiesSpawned = 0;
  final List<ZombieKind> _lastKinds = [];

  /// Segundos de separación mínima entre un zombi y el obstáculo fijo más
  /// cercano (en cualquier orden). Todos bajan a la misma velocidad, así que
  /// esa separación en el spawn es la que llega al jugador: nunca tiene que
  /// esquivar un zombi y un obstáculo a la vez.
  static const double _zombieClearance = 1.0;
  double _sinceObstacleSpawn = 999;
  double _sinceZombieSpawn = 999;

  /// Dificultad 0..1 para zombis: llega al máximo a los 90 s de partida.
  double get zombieDifficulty => (_elapsed / 90).clamp(0.0, 1.0).toDouble();

  /// Zombis vivos (expuesto para tests).
  List<ZombieObstacle> get zombies => List.unmodifiable(_zombies);
  double _coinCooldown = 2.0;
  double _powerUpCooldown = 10.0;
  double _difficultySpeed =
      260; // px/seg sobre la línea base, sube con el score
  double _elapsed = 0;
  double _scoreCarry = 0; // puntos de score aún no enteros

  /// Temblor de cámara que crece con la velocidad (ver [SpeedRumble]). Es solo
  /// visual; se puede apagar (accesibilidad o capturas de pantalla).
  bool speedRumbleEnabled = true;

  /// Segundos de partida antes de que aparezca el primer auto de dos carriles
  /// (los primeros segundos sirven para aprender los otros obstáculos).
  static const double carStartSeconds = 12;

  /// true si el último obstáculo generado fue un auto (nunca dos seguidos).
  bool _lastWasCar = false;

  // Geometría de perspectiva vigente (una sola fuente de verdad para el mapa,
  // los actores del corredor y el jugador con sus carriles).
  Perspective _perspective = const Perspective(width: 0, height: 0);

  /// Geometría de perspectiva activa.
  Perspective get perspective => _perspective;

  /// Regenera la perspectiva si cambió el tamaño y la propaga a los
  /// componentes vivos.
  void _syncPerspective() {
    if (_perspective.width == size.x && _perspective.height == size.y) return;
    _perspective = Perspective(width: size.x, height: size.y);
    for (final obstacle in _obstacles) {
      obstacle.perspective = _perspective;
    }
    for (final coin in _coins) {
      coin.perspective = _perspective;
    }
    for (final item in _powerUpItems) {
      item.perspective = _perspective;
    }
    for (final zombie in _zombies) {
      zombie.perspective = _perspective;
    }
    if (_hasPlayer) {
      // Al redimensionar solo se mueve la fila de suelo: carril y salto
      // se conservan.
      _player.perspective = _perspective;
      _player.setGroundY(size.y * 0.86);
    }
  }

  @override
  Future<void> onLoad() async {
    // Por si el juego se desmontó y se volvió a montar: los oyentes vuelven a
    // engancharse y el fundido se re-sincroniza con el tema vigente.
    _listenTheme();
    _listenMusic();
    _themeBlend = _themeTarget;
    _syncPerspective();
    _spawnPlayer();
    _applyStartUpgrades();
    // El corredor sale a correr: ahí empieza la música de la partida.
    _syncMusic();
  }

  @override
  void onRemove() {
    _unlistenTheme();
    _unlistenMusic();
    music.dispose(); // vuelta al menú: la música se corta y se libera
    super.onRemove();
  }

  void _listenTheme() {
    if (_listeningTheme) return;
    _listeningTheme = true;
    gameState.themeMode.addListener(_onThemePreferenceChanged);
    gameState.platformBrightness.addListener(_onThemePreferenceChanged);
  }

  void _unlistenTheme() {
    if (!_listeningTheme) return;
    _listeningTheme = false;
    gameState.themeMode.removeListener(_onThemePreferenceChanged);
    gameState.platformBrightness.removeListener(_onThemePreferenceChanged);
  }

  /// Blend (0..1) que corresponde al tema elegido ahora mismo.
  double get _themeTarget => gameState.isDark ? 1.0 : 0.0;

  /// El tema cambió: si el motor corre, [update] hace el fundido; si está
  /// pausado (pausa, game over, tienda) no corre ningún frame, así que se
  /// clava el valor y se pide un único paso para que el canvas repinte.
  void _onThemePreferenceChanged() {
    final target = _themeTarget;
    if (_themeBlend == target || !paused) return;
    _themeBlend = target;
    stepEngine();
  }

  /// Avanza el fundido del tema hacia su valor objetivo. Lo llama [update]
  /// cada frame; es público para que los tests midan la animación sin
  /// montar el motor.
  void advanceThemeFade(double dt) {
    final target = _themeTarget;
    if (_themeBlend == target) return;
    final step = dt / _themeFadeSeconds;
    _themeBlend = _themeBlend < target
        ? min(target, _themeBlend + step)
        : max(target, _themeBlend - step);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    _syncPerspective();
  }

  void _spawnPlayer() {
    _player = PlayerComponent(
      startPosition: Vector2(size.x / 2, size.y * 0.86),
      perspective: _perspective,
    );
    _hasPlayer = true;
    add(_player);
  }

  @override
  void update(double dt) {
    // Pausa del usuario: el mundo queda congelado. El motor está parado, así
    // que esto solo corre si alguien pidió un paso puntual (repintar tras un
    // cambio de tema) y ahí no se mueve nada.
    if (gameState.isPaused.value) return;

    // El fundido del tema se anima aunque la partida haya terminado.
    advanceThemeFade(dt);

    if (gameState.isGameOver.value) {
      // El mundo queda congelado (sin super.update: nada se mueve ni
      // spawnerea) y solo se disipa el feedback del golpe final. Recién
      // cuando termina se pausa el motor: de lo contrario el destello de la
      // muerte se congelaría a plena opacidad y la cámara quedaría corrida.
      juice.update(dt);
      if (_deathTimer > 0) {
        _deathTimer -= dt;
        if (_deathTimer <= 0) pauseEngine();
      }
      return;
    }

    super.update(dt);
    _syncPerspective();

    if (tutorialActive) {
      // Tutorial: solo el piso y el corredor se mueven. No avanza el reloj de
      // dificultad, así la primera partida real arranca desde cero.
      _map.update(dt, 260, _perspective);
      juice.update(dt);
      return;
    }

    _elapsed += dt;
    powerUps.update(dt);

    // Parpadeo mientras dure la invulnerabilidad (escudo recién roto o golpe
    // pagado con diamantes): el respiro se tiene que ver en el corredor.
    _player.blinkAlpha =
        (!powerUps.isInvulnerable || sin(_elapsed * 42) > 0) ? 1 : 0.3;

    // Polvo al aterrizar: en este frame el jugador pasó del aire al suelo.
    if (_wasAirborne && !_player.isAirborne) {
      juice.landDust(
        Offset(_player.position.x, _player.groundFeetY),
        blend: _themeBlend,
      );
    }
    _wasAirborne = _player.isAirborne;

    // Acumulador fraccionario: a 60 fps cada frame suma 0.33 puntos y
    // redondearlos directamente dejaba el score clavado en 0. El score corre a
    // doble mientras dure el multiplicador.
    _scoreCarry += dt * 20 * powerUps.scoreMultiplier;
    final wholeScore = _scoreCarry.truncate();
    if (wholeScore > 0) {
      gameState.addScore(wholeScore);
      _scoreCarry -= wholeScore;
    }
    _difficultySpeed = 260 + (_elapsed * 6); // se acelera con el tiempo
    // Las piernas siguen al piso: más rápido el mundo, más rápida la carrera.
    _player.runRate = (_difficultySpeed / 260).clamp(1.0, 1.9).toDouble();

    // El piso avanza a la misma velocidad que el juego: la sensación de
    // carrera crece junto con la dificultad.
    _map.update(dt, _difficultySpeed, _perspective);

    _sinceObstacleSpawn += dt;
    _sinceZombieSpawn += dt;

    _spawnCooldown -= dt;
    if (_spawnCooldown <= 0) {
      if (zombiesEnabled &&
          (_zombieDue || _sinceZombieSpawn < _zombieClearance)) {
        // Acaba de nacer un zombi (o está por nacer): el obstáculo espera
        // para no apelotonarse.
        _spawnCooldown =
            _zombieDue ? 0.1 : _zombieClearance - _sinceZombieSpawn;
      } else {
        _spawnObstacle();
        _spawnCooldown = max(0.45, 1.1 - _elapsed * 0.01);
      }
    }

    if (zombiesEnabled) {
      _zombieCooldown -= dt;
      if (_zombieCooldown <= 0) {
        if (_sinceObstacleSpawn < _zombieClearance) {
          // Obstáculo muy reciente: se frenan los nuevos obstáculos hasta
          // que se cumpla la separación y el zombi pueda salir.
          _zombieDue = true;
        } else {
          spawnZombie();
          _zombieDue = false;
          _zombieCooldown = _nextZombieDelay();
        }
      }
    }

    // Tandas de monedas e ítems de power-up, con su propia cadencia.
    _coinCooldown -= dt;
    if (_coinCooldown <= 0) {
      spawnCoinPattern();
      _coinCooldown = _nextCoinDelay();
    }
    _powerUpCooldown -= dt;
    if (_powerUpCooldown <= 0) {
      spawnPowerUp();
      _powerUpCooldown = _nextPowerUpDelay();
    }

    if (powerUps.isMagnetActive) _applyMagnet(dt);

    for (final obstacle in List<ObstacleComponent>.from(_obstacles)) {
      obstacle.speed = _difficultySpeed;
      // Colisión por fila + carril + altura (DepthComponent.collidesWith).
      // Mientras dure la invulnerabilidad (escudo recién roto o pago con
      // diamantes) el cruce no cuenta.
      final touching =
          !powerUps.isInvulnerable && obstacle.collidesWith(_player);
      if (touching && !obstacle.wasTouching) {
        _onCollision(); // una sola vez por cruce, no un frame atrás del otro
      }
      obstacle.wasTouching = touching;
      if (obstacle.offScreen) {
        obstacle.removeFromParent();
        _obstacles.remove(obstacle);
      }
    }

    for (final zombie in List<ZombieObstacle>.from(_zombies)) {
      zombie.speed = _difficultySpeed;
      zombie.targetLane = _player.lanePos;
      // Misma regla que los obstáculos: un solo golpe por cruce y nada
      // mientras dure la invulnerabilidad.
      final touching = !powerUps.isInvulnerable && zombie.collidesWith(_player);
      if (touching && !zombie.wasTouching) {
        _onCollision();
      }
      zombie.wasTouching = touching;
      if (zombie.offScreen) {
        zombie.removeFromParent();
        _zombies.remove(zombie);
      }
    }

    for (final coin in List<CoinComponent>.from(_coins)) {
      coin.speed = _difficultySpeed;
      if (coin.collidesWith(_player)) {
        gameState.collectDiamond(coin.value);
        if (hordeEnabled) horde.relieve(coin.value);
        juice.coinPickup(_centerOf(coin), value: coin.value);
        _removeCoin(coin);
      } else if (coin.offScreen) {
        _removeCoin(coin);
      }
    }

    for (final item in List<PowerUpComponent>.from(_powerUpItems)) {
      item.speed = _difficultySpeed;
      if (item.offScreen) {
        _removePowerUp(item);
        continue;
      }
      // Un escudo ya activo devuelve false: el ítem sigue volando y se
      // descarta al salir de pantalla en lugar de sumarse al pedo.
      if (item.collidesWith(_player)) _syncUpgrades();
      if (item.collidesWith(_player) && powerUps.apply(item.kind)) {
        gameState.recordEvent(ChallengeMetric.powerUps);
        juice.powerUpPickup(_centerOf(item), item.kind);
        _removePowerUp(item);
      }
    }

    if (hordeEnabled) _updateHorde(dt);

    juice.update(dt);
  }

  /// Avanza la horda y termina la partida si alcanzó al corredor.
  ///
  /// Cada vez que el jugador sobrevive un nivel más, la horda acelera: se
  /// avisa con un destello rojo y un temblor corto.
  void _updateHorde(double dt) {
    if (gameState.isGameOver.value) return;

    final leveledUp = horde.update(dt);
    if (leveledUp) {
      juice.flash(Juice.hitColor, 0.3, duration: 0.4);
      juice.addShake(3);
    }

    if (horde.caught) {
      // Mismo camino que el golpe mortal de un obstáculo: congela el
      // resultado, actualiza el récord y deja correr el juice de la muerte.
      gameState.finishRun();
      juice.death(Offset(_player.position.x, _player.position.y));
      _deathTimer = _deathGrace;
    }
  }

  /// Centro de pantalla de un actor del corredor: ahí nace su feedback.
  Offset _centerOf(DepthComponent actor) => Offset(
        actor.position.x + actor.size.x * 0.5,
        actor.position.y + actor.size.y * 0.5,
      );

  void _spawnObstacle() {
    // Carriles fijos (-1, 0, 1). La regla garantiza que entre los tres
    // obstáculos más cercanos nunca haya tres carriles distintos: el ritmo de
    // spawn (~0.95-1.1 s) deja ~160 px de separación a la altura del jugador,
    // así que la ventana de reacción (210 px) nunca contiene más de tres y
    // siempre queda un carril libre para esquivar.
    final feet = _player.groundFeetY;
    final ahead = _obstacles.where((o) => o.baseY < feet + 40).toList()
      ..sort((a, b) => b.baseY.compareTo(a.baseY)); // más cercano primero

    var kind = _rollKind();
    double? lane;
    if (kind == ObstacleKind.car) {
      lane = _carLane(ahead);
      if (lane == null) kind = ObstacleKind.block; // no hay carril libre seguro
    }
    lane ??= _nextLane(ahead);
    _lastWasCar = kind == ObstacleKind.car;

    final obstacle = ObstacleComponent(
      lane: lane,
      speed: _difficultySpeed,
      perspective: _perspective,
      kind: kind,
    );
    _obstacles.add(obstacle);
    add(obstacle);
    _sinceObstacleSpawn = 0;
  }

  // --- Zombis móviles ----------------------------------------------------------

  /// Segundos hasta el próximo zombi: de ~3,2-4,5 s al principio a ~1,8-3,1 s
  /// con la dificultad máxima (el azar suma hasta 1,3 s).
  double _nextZombieDelay() =>
      3.2 - 1.4 * zombieDifficulty + _rng.nextDouble() * 1.3;

  /// Elige el tipo del próximo zombi: los primeros tres son uno de cada tipo
  /// (lento, normal, rápido) para que el jugador conozca a los tres; después
  /// manda [ZombieKind.roll], sin repetir el mismo tipo más de dos veces
  /// seguidas.
  ZombieKind _pickZombieKind(double difficulty) {
    var kind = ZombieKind.roll(difficulty, _rng.nextDouble());
    if (_zombiesSpawned < ZombieKind.values.length) {
      kind = ZombieKind.values[_zombiesSpawned];
    } else if (_lastKinds.length >= 2 &&
        _lastKinds[_lastKinds.length - 1] == kind &&
        _lastKinds[_lastKinds.length - 2] == kind) {
      final others = ZombieKind.values.where((k) => k != kind).toList();
      kind = others[_rng.nextInt(others.length)];
    }
    _zombiesSpawned++;
    _lastKinds.add(kind);
    if (_lastKinds.length > 4) _lastKinds.removeAt(0);
    return kind;
  }

  /// Carril de base de un zombi nuevo según su tipo.
  double _zombieHomeLane(ZombieKind kind) {
    switch (kind) {
      case ZombieKind.slow:
        return _rng.nextBool() ? -0.5 : 0.5;
      case ZombieKind.normal:
        return 0.0;
      case ZombieKind.fast:
        return (_rng.nextInt(3) - 1).toDouble();
    }
  }

  /// Genera un zombi y lo suma a la partida.
  ///
  /// [kind] y [lane] son para tests y guiones; en el juego el tipo sale de la
  /// dificultad ([ZombieKind.roll]) y el carril de base depende del tipo: el
  /// lento patrulla un tramo de dos carriles, el normal todo el corredor y el
  /// rápido arranca en un carril cualquiera y después persigue al jugador.
  ZombieObstacle spawnZombie({ZombieKind? kind, double? lane}) {
    final difficulty = zombieDifficulty;
    final chosen = kind ?? _pickZombieKind(difficulty);
    final home = lane ?? _zombieHomeLane(chosen);
    final zombie = ZombieObstacle(
      lane: home,
      speed: _difficultySpeed,
      perspective: _perspective,
      kind: chosen,
      difficulty: difficulty,
      random: _rng,
    )..targetLane = _player.lanePos;
    _zombies.add(zombie);
    add(zombie);
    _sinceZombieSpawn = 0;
    return zombie;
  }

  /// Profundidad (px) alrededor de la fila de spawn en la que un obstáculo
  /// todavía cuenta como "vecino" del que está por nacer: ~2 spawns de
  /// separación. Dentro de esa franja el carril libre del auto tiene que
  /// seguir libre.
  static const double _carNeighbourhood = 320;

  /// Carril central (-0.5 o +0.5) para un auto de dos carriles, o null si no
  /// se puede garantizar un carril libre. El carril que queda libre es -1 (si
  /// el auto cubre 0 y +1) o +1 (si cubre -1 y 0); ese carril no puede estar
  /// ocupado por ningún obstáculo vecino. Se prefiere dejar libre el carril en
  /// el que ya está el jugador.
  double? _carLane(List<ObstacleComponent> ahead) {
    final spawnY = _perspective.yAtT(0.06);
    final near =
        ahead.where((o) => (o.baseY - spawnY).abs() < _carNeighbourhood);
    final candidates = <double>[
      for (final free in const [-1.0, 1.0])
        if (!near.any((o) => o.coversLane(free))) free,
    ];
    if (candidates.isEmpty) return null;
    final player = _player.lane.toDouble();
    final free = candidates.contains(player)
        ? player
        : candidates[_rng.nextInt(candidates.length)];
    return free < 0 ? 0.5 : -0.5; // el auto cubre el lado opuesto al libre
  }

  /// Carril para el próximo obstáculo, mirando los dos más cercanos que aún no
  /// pasaron al jugador (ver doc de [_spawnObstacle]).
  double _nextLane(List<ObstacleComponent> ahead) {
    const lanes = [-1.0, 0.0, 1.0];
    final currentLane = _player.lane.toDouble();

    // Con un auto de dos carriles recién generado, el siguiente obstáculo
    // cae dentro de los carriles que el auto ya bloquea: así el carril libre
    // sigue siendo una salida segura y nunca se arma una pared de tres.
    final spawnY = _perspective.yAtT(0.06);
    final recentCar = ahead.where((o) =>
        o.kind == ObstacleKind.car &&
        (o.baseY - spawnY).abs() < _carNeighbourhood);
    if (recentCar.isNotEmpty) {
      final covered = recentCar.first.coveredLanes;
      return covered[_rng.nextInt(covered.length)];
    }

    if (ahead.length >= 2) {
      final first = ahead[0].lane;
      final second = ahead[1].lane;
      if (first != second) {
        final pair = [first, second];
        final freeLanes =
            lanes.where((l) => pair.every((t) => (t - l).abs() > 0.5)).toList();

        // Si el jugador está en un carril aún libre, se prioriza para mantener
        // un ritmo legible y evitar muertes por suerte extrema en pruebas y
        // partidas cortas sin input.
        if (freeLanes.contains(currentLane)) {
          final preferred = [
            currentLane,
            ...freeLanes.where((l) => l != currentLane)
          ];
          return preferred[_rng.nextInt(preferred.length)];
        }

        return pair[_rng.nextInt(pair.length)];
      }

      final others = lanes.where((l) => (l - first).abs() > 0.5).toList();
      if (others.contains(currentLane)) {
        return currentLane;
      }
      return others[_rng.nextInt(others.length)];
    }

    final taken = ahead.map((o) => o.lane).toList();
    final free =
        lanes.where((l) => taken.every((t) => (t - l).abs() > 0.5)).toList();
    final pool = free.isEmpty ? lanes : free;

    if (pool.contains(currentLane) && _rng.nextDouble() < 0.7) {
      return currentLane;
    }

    return pool[_rng.nextInt(pool.length)];
  }

  /// Tipo de obstáculo con pesos: el contenedor (esquivar) es el más común.
  ObstacleKind _rollKind() {
    // 20 % de autos (si ya pasó el tramo de aprendizaje y el anterior no lo
    // fue); el resto reparte con los pesos de siempre.
    if (_elapsed >= carStartSeconds &&
        !_lastWasCar &&
        _rng.nextDouble() < 0.2) {
      return ObstacleKind.car;
    }
    final roll = _rng.nextDouble();
    if (roll < 0.4) return ObstacleKind.block;
    if (roll < 0.7) return ObstacleKind.lowBarrier;
    return ObstacleKind.overhead;
  }

  void _onCollision() {
    final at = Offset(_player.position.x, _player.position.y);

    // Primero intenta el escudo: si absorbe, el golpe no cuenta (y deja un
    // respiro de invulnerabilidad).
    if (powerUps.absorbHit()) {
      juice.shieldAbsorb(at);
      return;
    }

    // Sin escudo: cuesta una vida. Mientras queden corazones se sigue
    // corriendo (con un respiro para que no te peguen de nuevo en el acto);
    // con el último, se termina la partida.
    if (gameState.loseLife() > 0) {
      powerUps.grantInvulnerability();
      juice.hitPaid(at);
      // Tropezar deja a la horda más cerca (el escudo no: ya absorbió).
      if (hordeEnabled) horde.stumble();
    } else {
      // Única puerta de entrada al fin de partida: congela el resultado,
      // actualiza el récord y deja isGameOver en true para el overlay.
      gameState.finishRun();
      juice.death(at);
      _deathTimer = _deathGrace;
      // El motor NO se pausa acá: lo hace update() cuando el juice de la
      // muerte termina de disiparse (ver [_deathGrace]).
    }
  }

  // --- Monedas: patrones -------------------------------------------------------

  /// Segundos hasta la siguiente tanda de monedas.
  ///
  /// Más espaciadas que antes (3.4-5.0 s, antes 2.6-4.0 s): bajan ~20 % los
  /// diamantes por partida para que las mejoras de la tienda no se agoten en
  /// pocas carreras.
  double _nextCoinDelay() => 3.4 + _rng.nextDouble() * 1.6;

  /// Tipo de patrón con pesos: el barrido en línea es el más frecuente.
  CoinPattern _rollCoinPattern() {
    final roll = _rng.nextDouble();
    if (roll < 0.3) return CoinPattern.line;
    if (roll < 0.55) return CoinPattern.arc;
    if (roll < 0.75) return CoinPattern.zigzag;
    return CoinPattern.high;
  }

  /// Genera un patrón de monedas y lo suma a la partida.
  ///
  /// [anchorLane] fija el anclaje y [avoidObstacles] permite saltarse la
  /// validación de carril: los dos los usan los tests (y podrían usarlos
  /// scripts de nivel) cuando el escenario ya está controlado. En el juego
  /// normal se prueban varios anclajes hasta encontrar uno libre.
  ///
  /// Devuelve las monedas generadas (vacío si ningún anclaje quedó libre).
  List<CoinComponent> spawnCoinPattern({
    CoinPattern? pattern,
    double? anchorLane,
    bool avoidObstacles = true,
  }) {
    final chosen = pattern ?? _rollCoinPattern();
    final attempts = anchorLane != null ? 1 : 6;

    for (var i = 0; i < attempts; i++) {
      final candidates = chosen.anchorCandidates;
      final anchor = anchorLane ?? candidates[_rng.nextInt(candidates.length)];
      final coins = buildCoinPattern(
        pattern: chosen,
        perspective: _perspective,
        speed: _difficultySpeed,
        anchorLane: anchor,
      );
      if (!avoidObstacles || coins.every(_isFree)) {
        _coins.addAll(coins);
        for (final coin in coins) {
          add(coin);
        }
        return coins;
      }
    }
    return const [];
  }

  /// true si la moneda no está pegada a un obstáculo existente: mismo carril
  /// y (casi) la misma profundidad. Sin esto un patrón podría dejar gemas
  /// incrustadas en los contenedores —invisible e imposible de recoger—.
  bool _isFree(CoinComponent coin) =>
      _depthIsFree(coin.lane, coin.baseY, coin.laneHalfSpan);

  /// true si [lane] a la profundidad [baseY] no está ocupada por un obstáculo
  /// (comparado en unidades de carril: ambos actores están a la misma
  /// profundidad, así que los anchos son directamente comparables).
  bool _depthIsFree(double lane, double baseY, double halfSpan) {
    for (final obstacle in _obstacles) {
      if ((obstacle.baseY - baseY).abs() > 28) continue;
      if ((obstacle.lane - lane).abs() < obstacle.laneHalfSpan + halfSpan) {
        return false;
      }
    }
    return true;
  }

  // --- Power-ups ---------------------------------------------------------------

  /// Segundos hasta el siguiente power-up.
  ///
  /// La mejora "Buena racha" lo acorta un 15 % por nivel.
  double _nextPowerUpDelay() {
    final luck = gameState.upgradeLevel(UpgradeIds.luck);
    return (14 + _rng.nextDouble() * 8) * (1 - 0.15 * luck);
  }

  PowerUpKind _rollPowerUpKind() {
    final roll = _rng.nextDouble();
    if (roll < 0.4) return PowerUpKind.shield;
    if (roll < 0.7) return PowerUpKind.magnet;
    return PowerUpKind.multiplier;
  }

  /// Genera un power-up suelto y lo suma a la partida.
  ///
  /// Igual que [spawnCoinPattern]: [lane] y [avoidObstacles] son para tests y
  /// guiones; el juego elige carril entre los tres fijos (centro primero) y
  /// devuelve `null` si ninguno quedó libre en esta tanda.
  PowerUpComponent? spawnPowerUp({
    PowerUpKind? kind,
    double? lane,
    bool avoidObstacles = true,
  }) {
    final chosen = kind ?? _rollPowerUpKind();
    final candidates = lane != null ? <double>[lane] : <double>[0.0, -1.0, 1.0]
      ..shuffle(_rng);

    for (final candidate in candidates) {
      final item = buildPowerUp(
        kind: chosen,
        perspective: _perspective,
        speed: _difficultySpeed,
        lane: candidate,
      );
      if (!avoidObstacles ||
          _depthIsFree(item.lane, item.baseY, item.laneHalfSpan)) {
        _powerUpItems.add(item);
        add(item);
        return item;
      }
    }
    return null;
  }

  /// Ventana vertical (px antes de los pies del jugador) en la que el imán
  /// atrapa monedas. Entra tarde a propósito: las monedas siguen su recorrido
  /// normal hasta que están a ~0.8 s del jugador.
  static const double _magnetWindow = 240;

  /// Carriles por segundo que tarda una moneda en caer en el carril del
  /// jugador (0.9 carriles ≈ 0.23 s, más rápido que el jugador: se siente
  /// como un "chupón").
  static const double _magnetSpeed = 4.0;

  /// Atrae hacia el carril del jugador las monedas dentro de la ventana del
  /// imán. Solo mueve el carril: la profundidad la gobierna la ley de
  /// perspectiva, así la moneda no "teletransporta" hacia el jugador.
  void _applyMagnet(double dt) {
    final feet = _player.groundFeetY;
    for (final coin in _coins) {
      if (coin.baseY < feet - _magnetWindow || coin.baseY > feet + 40) continue;
      final diff = _player.lanePos - coin.lane;
      if (diff.abs() < 0.0005) continue;
      final step = _magnetSpeed * dt;
      coin.lane =
          diff.abs() <= step ? _player.lanePos : coin.lane + step * diff.sign;
      coin.syncGeometry();
    }
  }

  void _removeCoin(CoinComponent coin) {
    coin.removeFromParent();
    _coins.remove(coin);
  }

  void _removePowerUp(PowerUpComponent item) {
    item.removeFromParent();
    _powerUpItems.remove(item);
  }

  // --- Entrada: gestos en pantalla -------------------------------------------
  // Acumulamos los deltas del arrastre hasta cruzar el umbral y ahí disparamos
  // UNA acción por gesto, eligiendo el eje dominante:
  //   ← / →  cambia de carril
  //   ↑      salta
  //   ↓      se agacha (o se tira si está en el aire)
  /// Arrastre (px) que confirma un gesto con sensibilidad 1.0.
  static const double baseSwipeThreshold = 22;

  /// Arrastre efectivo según la sensibilidad elegida por el usuario: más
  /// sensibilidad = gesto más corto (0.5 -> 44 px, 1.0 -> 22 px, 2.0 -> 11 px).
  double get swipeThreshold =>
      baseSwipeThreshold / gameState.swipeSensitivity.value;

  double _swipeX = 0;
  double _swipeY = 0;

  /// true cuando el gesto en curso ya disparó su acción (así un arrastre
  /// largo o partido en varios eventos no encadena varias acciones).
  bool _gestureConsumed = false;

  @override
  void onPanStart(DragStartInfo info) {
    _swipeX = 0;
    _swipeY = 0;
    _gestureConsumed = false;
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (gameState.isGameOver.value ||
        gameState.isPaused.value ||
        _gestureConsumed) {
      return;
    }
    _syncPerspective();

    final delta = info.delta.global;
    _swipeX += delta.x;
    _swipeY += delta.y;

    final threshold = swipeThreshold;
    final doneX = _swipeX.abs() >= threshold;
    final doneY = _swipeY.abs() >= threshold;
    if (!doneX && !doneY) return;

    // Eje dominante: el más largo manda; en empate decide el horizontal.
    if (!doneY || (doneX && _swipeX.abs() >= _swipeY.abs())) {
      final dir = _swipeX > 0 ? 1 : -1;
      _player.moveLane(dir);
      onAction?.call(dir > 0 ? RunnerAction.moveRight : RunnerAction.moveLeft);
    } else if (_swipeY < 0) {
      if (_player.jump()) {
        if (!tutorialActive) gameState.recordEvent(ChallengeMetric.jumps);
        onAction?.call(RunnerAction.jump);
      }
    } else {
      if (_player.roll()) {
        if (!tutorialActive) gameState.recordEvent(ChallengeMetric.rolls);
        onAction?.call(RunnerAction.roll);
      }
    }

    // Un gesto = una acción; se limpia para no encadenar por inercia.
    _swipeX = 0;
    _swipeY = 0;
    _gestureConsumed = true;
  }

  @override
  void onPanEnd(DragEndInfo info) {
    _swipeX = 0;
    _swipeY = 0;
    _gestureConsumed = false;
  }

  @override
  void render(Canvas canvas) {
    _syncPerspective();

    // Sacudida de cámara: vaivén + un escalado mínimo (overscan) para que el
    // borde del mapa nunca asome mientras tiembla. El juice entra dentro de
    // la traslación porque es parte del mundo; el HUD se dibuja después, fuera
    // del temblor: es interfaz, no corredor.
    // A eso se suma el temblor suave por velocidad ([SpeedRumble]): su cota
    // entra en el mismo sobreescaneo, así el borde tampoco asoma con él.
    final shake = juice.shake;
    final rumbleOn = speedRumbleEnabled &&
        !tutorialActive &&
        !gameState.isPaused.value &&
        !gameState.isGameOver.value;
    final rumbleAmp = rumbleOn ? SpeedRumble.amplitude(_difficultySpeed) : 0.0;
    final extent = shake + rumbleAmp;
    canvas.save();
    if (extent > 0) {
      final overscan = 1.0 + (2 * extent) / max(1.0, min(size.x, size.y));
      canvas.translate(size.x * 0.5, size.y * 0.5);
      canvas.scale(overscan, overscan);
      canvas.translate(-size.x * 0.5, -size.y * 0.5);
      var offset = shake > 0 ? juice.shakeOffset : Offset.zero;
      if (rumbleAmp > 0) {
        offset += SpeedRumble.offsetAt(_elapsed, _difficultySpeed);
      }
      canvas.translate(offset.dx, offset.dy);
    }

    // Mapa: cielo, parallax, corredor y piso animado (dibujado siempre
    // antes de los componentes para que queden encima).
    _map.render(
      canvas,
      _perspective,
      blend: _themeBlend,
      playerX: _player.position.x,
    );
    // La horda va debajo del corredor y los obstáculos (ellos se leen
    // primero), pero encima del mapa. No hay horda en el tutorial.
    if (hordeEnabled && !tutorialActive) {
      horde.render(canvas, _perspective, playerFeetY: _player.groundFeetY);
    }
    super.render(canvas);
    juice.render(canvas);
    // Ambientación final (velo, viñeta, ceniza): integra horda, zombis y
    // obstáculos en la misma atmósfera.
    _map.renderGrade(
      canvas,
      _perspective,
      blend: _themeBlend,
    );

    canvas.restore();

    // Destello en viñeta sobre el mundo, sin sacudir ni teñir el HUD.
    juice.renderFlash(canvas, Offset.zero & Size(size.x, size.y));
    _renderPowerUpHud(canvas);
  }

  /// HUD de power-ups en la esquina superior derecha del corredor: se dibuja
  /// en el propio canvas del juego (la Fase 2 lo dejó fuera de los widgets de
  /// Flutter, sin tocar el header ni la botonera).
  void _renderPowerUpHud(Canvas canvas) {
    final rows = <({PowerUpKind kind, double progress})>[];
    if (powerUps.hasShield) {
      rows.add((kind: PowerUpKind.shield, progress: 1)); // carga completa
    }
    if (powerUps.isMagnetActive) {
      rows.add((
        kind: PowerUpKind.magnet,
        progress: powerUps.magnetTimer / powerUps.magnetDuration,
      ));
    }
    if (powerUps.isMultiplierActive) {
      rows.add((
        kind: PowerUpKind.multiplier,
        progress: powerUps.multiplierTimer / powerUps.multiplierDuration,
      ));
    }
    if (rows.isEmpty) return;

    const tile = 38.0; // lado de la ficha
    const inset = 3.0; // aire entre la ficha y su celda
    const barGap = 6.0; // separación ficha -> barra
    const barHeight = 4.0;
    const gap = 8.0; // separación entre filas
    const margin = 10.0;
    const pad = 6.0; // margen interno de la placa

    const rowH = tile + inset * 2 + barGap + barHeight;
    const blockW = tile + inset * 2;
    final totalH = rows.length * rowH + (rows.length - 1) * gap;
    final plate = Rect.fromLTWH(
      size.x - margin - (blockW + pad * 2),
      margin,
      blockW + pad * 2,
      totalH + pad * 2,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plate, const Radius.circular(14)),
      Paint()..color = const Color(0xFF0B1224).withValues(alpha: 0.55),
    );

    var y = plate.top + pad;
    final blockLeft = plate.left + pad;
    for (final row in rows) {
      final tileRect = Rect.fromLTWH(blockLeft + inset, y + inset, tile, tile);
      PowerUpComponent.drawBadge(canvas, row.kind, tileRect, 1);

      final track = Rect.fromLTWH(
        tileRect.left,
        tileRect.bottom + barGap,
        tile,
        barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(track, const Radius.circular(2)),
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.25),
      );
      final progress = row.progress.clamp(0.0, 1.0);
      if (progress > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
                track.left, track.top, track.width * progress, track.height),
            const Radius.circular(2),
          ),
          Paint()..color = row.kind.color,
        );
      }
      y += rowH + gap;
    }
  }

  /// Revive tras el anuncio rewarded: sigue la MISMA partida (puntaje y
  /// diamantes se conservan) con una vida, la horda más atrás, el camino
  /// despejado y un respiro de invulnerabilidad. Una vez por partida.
  void reviveRun() {
    if (!gameState.revive()) return;
    for (final obstacle in _obstacles) {
      obstacle.removeFromParent();
    }
    _obstacles.clear();
    for (final zombie in _zombies) {
      zombie.removeFromParent();
    }
    _zombies.clear();
    _zombieCooldown = _firstZombieDelay;
    _zombieDue = false;
    _sinceObstacleSpawn = 0;
    _sinceZombieSpawn = 0;
    horde.revive();
    juice.reset();
    _deathTimer = 0;
    powerUps.invulnerableTimer = reviveInvulnerability;
    _swipeX = 0;
    _swipeY = 0;
    _gestureConsumed = false;
    resumeEngine();
  }

  /// Segundos de invulnerabilidad al revivir (más largo que el de un golpe).
  static const double reviveInvulnerability = 2.5;

  /// Llamado desde la botonera externa (fuera del juego).
  void restartRun() {
    // La partida empieza de cero: mientras se limpia, los oyentes de música
    // no reanudan la pista vieja (ver [_restartingRun]).
    _restartingRun = true;
    try {
      _map.resetRun(); // el mapa vuelve al desierto y a sus props iniciales
      for (final obstacle in _obstacles) {
        obstacle.removeFromParent();
      }
      _obstacles.clear();
      for (final zombie in _zombies) {
        zombie.removeFromParent();
      }
      _zombies.clear();
      _zombieCooldown = _firstZombieDelay;
      _zombieDue = false;
      _zombiesSpawned = 0;
      _lastKinds.clear();
      _sinceObstacleSpawn = 999;
      _sinceZombieSpawn = 999;
      for (final coin in _coins) {
        coin.removeFromParent();
      }
      _coins.clear();
      for (final item in _powerUpItems) {
        item.removeFromParent();
      }
      _powerUpItems.clear();
      powerUps.reset();
      juice.reset();
      _wasAirborne = false;
      _deathTimer = 0;
      _coinCooldown = 2.0;
      _powerUpCooldown = 10.0;
      _elapsed = 0;
      _lastWasCar = false;
      _difficultySpeed = 260;
      _scoreCarry = 0;
      horde.reset();
      gameState.resetRun();
      _player.resetTo(
        startPosition: Vector2(size.x / 2, size.y * 0.86),
      );
      _swipeX = 0;
      _swipeY = 0;
      _gestureConsumed = false;
      _applyStartUpgrades();
      resumeEngine();
    } finally {
      _restartingRun = false;
    }
    // Corrida nueva: el tema arranca desde el principio (o queda cortado si
    // el jugador lo apagó en Ajustes).
    if (gameState.musicEnabled.value) {
      music.start();
    } else {
      music.pause();
    }
  }

  /// Pasa a los power-ups las duraciones que dan las mejoras compradas:
  /// +2 s por nivel sobre la base de 6 s (imán) y 8 s (x2).
  void _syncUpgrades() {
    powerUps
      ..magnetDuration = 6 + 2.0 * gameState.upgradeLevel(UpgradeIds.magnet)
      ..multiplierDuration =
          8 + 2.0 * gameState.upgradeLevel(UpgradeIds.multiplier);
  }

  /// Mejoras que actúan al arrancar la partida (escudo inicial). No en el
  /// tutorial: ahí no hay golpes.
  void _applyStartUpgrades() {
    _syncUpgrades();
    if (tutorialActive) return;
    if (gameState.upgradeLevel(UpgradeIds.startShield) > 0) {
      powerUps.apply(PowerUpKind.shield);
    }
    // Imán y x2 de arranque: segundos de regalo al empezar la partida.
    powerUps
      ..magnetTimer =
          3.0 * gameState.upgradeLevel(UpgradeIds.startMagnet)
      ..multiplierTimer =
          3.0 * gameState.upgradeLevel(UpgradeIds.startMultiplier);
  }
}
