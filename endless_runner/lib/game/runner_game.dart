import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../state/game_state.dart';
import '../state/rewards.dart';
import 'coin_component.dart';
import 'depth_component.dart';
import 'juice.dart';
import 'map_renderer.dart';
import 'player_component.dart';
import 'obstacle_component.dart';
import 'perspective.dart';
import 'power_up_component.dart';
import 'power_up_state.dart';

/// Acciones que el jugador dispara con un gesto. El tutorial las escucha para
/// saber si el usuario hizo lo que se le pidió.
enum RunnerAction { moveLeft, moveRight, jump, roll }

class RunnerGame extends FlameGame with PanDetector, HasCollisionDetection {
  RunnerGame({required this.gameState});

  final GameState gameState;

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
  void pauseGame() {
    if (!canPause) return;
    gameState.isPaused.value = true;
    gameState.save(); // la pausa es buen momento para persistir lo recolectado
    pauseEngine();
  }

  /// Reanuda una partida pausada con [pauseGame].
  void resumeGame() {
    if (!gameState.isPaused.value) return;
    gameState.isPaused.value = false;
    resumeEngine();
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
  final List<CoinComponent> _coins = [];
  final List<PowerUpComponent> _powerUpItems = [];
  final Random _rng = Random();
  final MapRenderer _map = MapRenderer();

  double _spawnCooldown = 0;
  double _coinCooldown = 2.0;
  double _powerUpCooldown = 10.0;
  double _difficultySpeed =
      260; // px/seg sobre la línea base, sube con el score
  double _elapsed = 0;
  double _scoreCarry = 0; // puntos de score aún no enteros

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
    if (_hasPlayer) {
      // Al redimensionar solo se mueve la fila de suelo: carril y salto
      // se conservan.
      _player.perspective = _perspective;
      _player.setGroundY(size.y * 0.86);
    }
  }

  @override
  Future<void> onLoad() async {
    _syncPerspective();
    _spawnPlayer();
    _applyStartUpgrades();
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
        dark: gameState.themeMode.value == ThemeMode.dark,
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

    // El piso avanza a la misma velocidad que el juego: la sensación de
    // carrera crece junto con la dificultad.
    _map.update(dt, _difficultySpeed, _perspective);

    _spawnCooldown -= dt;
    if (_spawnCooldown <= 0) {
      _spawnObstacle();
      _spawnCooldown = max(0.45, 1.1 - _elapsed * 0.01);
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

    for (final coin in List<CoinComponent>.from(_coins)) {
      coin.speed = _difficultySpeed;
      if (coin.collidesWith(_player)) {
        gameState.collectDiamond(coin.value);
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

    juice.update(dt);
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

    final obstacle = ObstacleComponent(
      lane: _nextLane(ahead),
      speed: _difficultySpeed,
      perspective: _perspective,
      kind: _rollKind(),
    );
    _obstacles.add(obstacle);
    add(obstacle);
  }

  /// Carril para el próximo obstáculo, mirando los dos más cercanos que aún no
  /// pasaron al jugador (ver doc de [_spawnObstacle]).
  double _nextLane(List<ObstacleComponent> ahead) {
    const lanes = [-1.0, 0.0, 1.0];
    final currentLane = _player.lane.toDouble();

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
  double _nextCoinDelay() => 2.6 + _rng.nextDouble() * 1.4;

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
  double _nextPowerUpDelay() => 14 + _rng.nextDouble() * 8;

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
    final shake = juice.shake;
    canvas.save();
    if (shake > 0) {
      final overscan = 1.0 + (2 * shake) / max(1.0, min(size.x, size.y));
      canvas.translate(size.x * 0.5, size.y * 0.5);
      canvas.scale(overscan, overscan);
      canvas.translate(-size.x * 0.5, -size.y * 0.5);
      final offset = juice.shakeOffset;
      canvas.translate(offset.dx, offset.dy);
    }

    // Mapa: cielo, parallax, corredor y piso animado (dibujado siempre
    // antes de los componentes para que queden encima).
    _map.render(
      canvas,
      _perspective,
      dark: gameState.themeMode.value == ThemeMode.dark,
      playerX: _player.position.x,
    );
    super.render(canvas);
    juice.render(canvas);

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

  /// Llamado desde la botonera externa (fuera del juego).
  void restartRun() {
    for (final obstacle in _obstacles) {
      obstacle.removeFromParent();
    }
    _obstacles.clear();
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
    _difficultySpeed = 260;
    _scoreCarry = 0;
    gameState.resetRun();
    _player.resetTo(
      startPosition: Vector2(size.x / 2, size.y * 0.86),
    );
    _swipeX = 0;
    _swipeY = 0;
    _gestureConsumed = false;
    _applyStartUpgrades();
    resumeEngine();
  }

  /// Pasa a los power-ups las duraciones que dan las mejoras compradas:
  /// +2 s por nivel sobre la base de 6 s (imán) y 8 s (x2).
  void _syncUpgrades() {
    powerUps
      ..magnetDuration =
          6 + 2.0 * gameState.upgradeLevel(UpgradeIds.magnet)
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
  }
}
