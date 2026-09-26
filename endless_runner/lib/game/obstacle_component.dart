import 'package:flame/components.dart';
import 'package:flutter/material.dart';

/// Obstaculo que viaja de arriba (chico, cerca del punto de fuga)
/// hacia abajo (grande, cerca del jugador), simulando profundidad 2.5D.
class ObstacleComponent extends PositionComponent {
  ObstacleComponent({
    required this.laneX, // posicion X "de destino" en el fondo del corredor
    required double speed,
    Vector2? screenSize,
  })  : _speed = speed,
        _screenHeight = screenSize?.y ?? 640,
        super(position: Vector2(laneX, 0), size: Vector2.all(10));

  final double laneX;
  final double _speed;
  final double _screenHeight;
  final Paint _paint = Paint()..color = const Color(0xFFE24B4A);
  bool passed = false;

  double get _depth => (position.y / _screenHeight).clamp(0.0, 1.0);

  @override
  void update(double dt) {
    super.update(dt);
    position.y += _speed * dt;
    final scale = 0.15 + _depth * 0.85; // chico arriba, grande abajo
    size = Vector2.all(44 * scale);
    // se acerca levemente al centro del corredor a medida que baja
    position.x = laneX;
  }

  @override
  void render(Canvas canvas) {
    final rect = Rect.fromCenter(
      center: Offset(size.x / 2, size.y / 2),
      width: size.x,
      height: size.y,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      _paint,
    );
  }

  Rect get hitBox => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: size.x * 0.8,
        height: size.y * 0.8,
      );

  bool get offScreen => position.y - size.y > _screenHeight;
}
