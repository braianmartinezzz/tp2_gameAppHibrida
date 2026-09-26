import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../state/game_state.dart';
import 'player_component.dart';
import 'obstacle_component.dart';

class RunnerGame extends FlameGame with PanDetector, HasCollisionDetection {
  RunnerGame({required this.gameState});

  final GameState gameState;

  late PlayerComponent _player;
  final List<ObstacleComponent> _obstacles = [];
  final Random _rng = Random();

  double _spawnCooldown = 0;
  double _difficultySpeed = 260; // px/seg, sube con el score
  double _elapsed = 0;

  // Puntos de fuga / bordes del corredor en X (relativo al alto de pantalla)
  double get _vanishX => size.x / 2;
  double get _laneMinX => size.x * 0.18;
  double get _laneMaxX => size.x * 0.82;

  @override
  Future<void> onLoad() async {
    _spawnPlayer();
  }

  void _spawnPlayer() {
    _player = PlayerComponent(
      startPosition: Vector2(size.x / 2, size.y * 0.86),
    );
    add(_player);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (gameState.isGameOver.value) return;

    _elapsed += dt;
    gameState.addScore((dt * 20).round());
    _difficultySpeed = 260 + (_elapsed * 6); // se acelera con el tiempo

    _spawnCooldown -= dt;
    if (_spawnCooldown <= 0) {
      _spawnObstacle();
      _spawnCooldown = max(0.45, 1.1 - _elapsed * 0.01);
    }

    for (final obstacle in List<ObstacleComponent>.from(_obstacles)) {
      if (obstacle.hitBox.overlaps(_player.hitBox) &&
          (obstacle.position.y - _player.position.y).abs() < 30) {
        _onCollision();
      }
      if (obstacle.offScreen) {
        obstacle.removeFromParent();
        _obstacles.remove(obstacle);
      }
    }
  }

  void _spawnObstacle() {
    final laneX = _laneMinX + _rng.nextDouble() * (_laneMaxX - _laneMinX);
    final obstacle = ObstacleComponent(
      laneX: laneX,
      speed: _difficultySpeed,
      screenSize: size,
    );
    _obstacles.add(obstacle);
    add(obstacle);
  }

  void _onCollision() {
    // Simulado: perder diamantes o terminar la partida.
    if (gameState.diamonds.value >= 10) {
      gameState.spendDiamonds(10); // "revivir" gastando diamantes
    } else {
      gameState.isGameOver.value = true;
      pauseEngine();
    }
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    if (gameState.isGameOver.value) return;
    final dx = info.delta.global.x;
    _player.moveTo(_player.position.x + dx, _laneMinX, _laneMaxX);
  }

  /// Dibuja el corredor en perspectiva (paredes convergentes) como fondo estatico.
  @override
  void render(Canvas canvas) {
    _renderCorridor(canvas);
    super.render(canvas);
  }

  void _renderCorridor(Canvas canvas) {
    final wallPaint = Paint()
      ..color = const Color(0xFF888780)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final vanish = Offset(_vanishX, size.y * 0.12);
    final corners = [
      Offset(0, size.y),
      Offset(size.x, size.y),
      Offset(size.x * 0.2, 0),
      Offset(size.x * 0.8, 0),
    ];
    for (final corner in corners) {
      canvas.drawLine(corner, vanish, wallPaint);
    }
  }

  /// Llamado desde la botonera externa (fuera del juego).
  void restartRun() {
    for (final obstacle in _obstacles) {
      obstacle.removeFromParent();
    }
    _obstacles.clear();
    _elapsed = 0;
    _difficultySpeed = 260;
    gameState.resetRun();
    _player.position = Vector2(size.x / 2, size.y * 0.86);
    resumeEngine();
  }
}
