import 'package:flame/components.dart';
import 'package:flutter/material.dart';

class PlayerComponent extends PositionComponent {
  static const double playerSize = 34;

  PlayerComponent({required Vector2 startPosition})
      : super(
          position: startPosition,
          size: Vector2.all(playerSize),
          anchor: Anchor.center,
        );

  final Paint _paint = Paint()..color = const Color(0xFF378ADD);

  /// Mueve al jugador en X, limitado a los bordes del corredor.
  void moveTo(double targetX, double minX, double maxX) {
    position.x = targetX.clamp(minX, maxX);
  }

  @override
  void render(Canvas canvas) {
    // Cuerpo simple tipo "palito" (placeholder: reemplazar por sprite/animación)
    final cx = size.x / 2;
    canvas.drawCircle(Offset(cx, 6), 6, _paint);
    canvas.drawLine(Offset(cx, 12), Offset(cx, 26), _paint..strokeWidth = 3);
    canvas.drawLine(Offset(cx, 18), Offset(cx - 8, 24), _paint);
    canvas.drawLine(Offset(cx, 18), Offset(cx + 8, 24), _paint);
    canvas.drawLine(Offset(cx, 26), Offset(cx - 6, 34), _paint);
    canvas.drawLine(Offset(cx, 26), Offset(cx + 6, 34), _paint);
  }

  Rect get hitBox => Rect.fromCenter(
        center: Offset(position.x, position.y),
        width: playerSize * 0.7,
        height: playerSize,
      );
}
