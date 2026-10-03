import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'depth_component.dart';

/// Tipo de obstáculo. Cada uno exige un gesto distinto, como en Subway
/// Surfers: la banda de altura es la que decide si lo pasás o no.
enum ObstacleKind {
  /// Valla baja: **se salta** (banda 0..16 sobre el suelo).
  lowBarrier,

  /// Losa colgante: **hay que agacharse** (banda 24..130; saltar no sirve,
  /// la losa sigue hacia arriba).
  overhead,

  /// Contenedor alto: **hay que cambiar de carril** (banda 0..90, más alto
  /// que el techo del salto ~60 px).
  block,
}

/// Obstáculo proyectado en perspectiva 2.5D.
///
/// Hereda de [DepthComponent] la ley de movimiento (la línea de suelo
/// `baseY` avanza con la aceleración de perspectiva) y la colisión por fila
/// + carril + altura. Acá solo queda lo propio del obstáculo: la banda de
/// altura de cada tipo y su dibujo.
class ObstacleComponent extends DepthComponent {
  ObstacleComponent({
    required super.lane,
    required super.speed,
    required super.perspective,
    this.kind = ObstacleKind.block,
  }) : super(
          position: Vector2.zero(),
          size: Vector2.all(1),
          anchor: Anchor.topLeft,
        ) {
    syncGeometry();
  }

  /// Tamaño de referencia en la línea base (t = 1).
  static const double baseSize = 44;

  static const Color _red = Color(0xFFE24B4A);
  static const Color _redDark = Color(0xFF8E2B2A);
  static const Color _hazard = Color(0xFFF2B33D);
  static const Color _hazardDark = Color(0xFF2B2318);

  /// Obstáculo a dibujar (define la banda de altura).
  final ObstacleKind kind;

  /// true si en el frame anterior estaba tocando al jugador.
  bool wasTouching = false;

  /// Distancia de la base al borde inferior de la caja (en px de pantalla):
  /// con ella se mide la altura sobre el suelo de cada tipo.
  double _bandMinPx = 0;

  /// Ancho útil, banda `[min, max]` sobre el suelo, en px sobre la línea base.
  ({double width, double bandMin, double bandMax}) get _spec => switch (kind) {
        ObstacleKind.lowBarrier => (width: 52, bandMin: 0, bandMax: 16),
        ObstacleKind.overhead => (width: 46, bandMin: 24, bandMax: 130),
        ObstacleKind.block => (width: baseSize, bandMin: 0, bandMax: 90),
      };

  @override
  void update(double dt) {
    super.update(dt);
    advance(dt); // aceleración de perspectiva compartida (DepthComponent)
    syncGeometry();
  }

  /// Recalcula posición, tamaño y banda a partir de [baseY].
  void syncGeometry() {
    final s = depthScale;
    final spec = _spec;
    final w = spec.width * s;
    final h = (spec.bandMax - spec.bandMin) * s;
    _bandMinPx = spec.bandMin * s;
    position.setValues(
      centerX - w * 0.5,
      baseY - spec.bandMax * s,
    );
    size.setValues(w, h);
  }

  // --- Dibujo ----------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final a = alpha;
    if (a <= 0) return;
    final w = size.x;
    final h = size.y;
    final groundY = h + _bandMinPx; // línea de suelo en coordenadas locales

    // Sombra proyectada en el piso: apoya el obstáculo en la ruta.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, groundY),
        width: w * 0.95,
        height: (groundY * 0.06 + 3).clamp(3.0, 12.0),
      ),
      Paint()
        ..color = const Color(0xFF000000).withValues(alpha: 0.26 * a),
    );

    switch (kind) {
      case ObstacleKind.lowBarrier:
        _drawBarrier(canvas, w, h);
      case ObstacleKind.overhead:
        _drawOverhead(canvas, w, h, groundY);
      case ObstacleKind.block:
        _drawBlock(canvas, w, h);
    }
  }

  /// Valla baja: barra ámbar con franjas oscuras (se salta).
  void _drawBarrier(Canvas canvas, double w, double h) {
    final a = alpha;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular((h * 0.28).clamp(1.0, 6.0)),
    );
    // Relleno con degradé vertical: más claro arriba, da volumen a la valla.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFFFD36B).withValues(alpha: a),
            _hazard.withValues(alpha: a),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    final dark = Paint()..color = _hazardDark.withValues(alpha: 0.85 * a);
    for (var i = 0; i < 3; i++) {
      canvas.drawRect(
        Rect.fromLTWH(w * (0.2 + i * 0.26), h * 0.18, w * 0.09, h * 0.64),
        dark,
      );
    }
    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF1B2233).withValues(alpha: 0.5 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  /// Losa colgante con franjas de peligro (hay que agacharse).
  void _drawOverhead(Canvas canvas, double w, double h, double groundY) {
    final a = alpha;
    final border = Paint()
      ..color = const Color(0xFF1B2233).withValues(alpha: 0.55 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Patas que la sostienen desde el suelo (fuera de la banda de colisión:
    // están a los costados, el jugador pasa por debajo).
    final leg = Paint()..color = _hazardDark.withValues(alpha: a);
    final legW = (w * 0.07).clamp(2.0, 8.0);
    canvas.drawRect(Rect.fromLTWH(0, h, legW, groundY - h), leg);
    canvas.drawRect(Rect.fromLTWH(w - legW, h, legW, groundY - h), leg);

    final body = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        body,
        Radius.circular((w * 0.08).clamp(1.0, 6.0)),
      ),
      Paint()..color = _hazard.withValues(alpha: a),
    );

    // Franjas diagonales de peligro, recortadas a la losa.
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        body,
        Radius.circular((w * 0.08).clamp(1.0, 6.0)),
      ),
    );
    final stripe = Paint()..color = _hazardDark.withValues(alpha: 0.9 * a);
    final step = w / 3.0;
    for (var i = -2; i < 6; i++) {
      final x = i * step;
      canvas.drawPath(
        Path()
          ..moveTo(x, h)
          ..lineTo(x + step * 0.5, h)
          ..lineTo(x + step * 0.5 + h, 0)
          ..lineTo(x + h, 0)
          ..close(),
        stripe,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        body,
        Radius.circular((w * 0.08).clamp(1.0, 6.0)),
      ),
      border,
    );
  }

  /// Contenedor alto con tapa y costuras (hay que esquivarlo de carril).
  void _drawBlock(Canvas canvas, double w, double h) {
    final a = alpha;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular((w * 0.12).clamp(1.0, 7.0)),
    );
    // Degradé rojo: tapa luminosa arriba y sombra abajo (efecto 3D de caja).
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFFF8A80).withValues(alpha: a),
            _red.withValues(alpha: a),
            _redDark.withValues(alpha: a),
          ],
          stops: const [0.0, 0.4, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Tapa superior más clara: da volumen al bloque.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.08, h * 0.06, w * 0.84, h * 0.1),
      Paint()..color = const Color(0xFFF2706F).withValues(alpha: a),
    );
    // Costuras verticales.
    final dark = Paint()..color = _redDark.withValues(alpha: 0.7 * a);
    canvas.drawRect(Rect.fromLTWH(w * 0.2, h * 0.2, w * 0.07, h * 0.74), dark);
    canvas.drawRect(Rect.fromLTWH(w * 0.73, h * 0.2, w * 0.07, h * 0.74), dark);
    // Reflejo vertical sobre el costado izquierdo.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.05, h * 0.2, w * 0.06, h * 0.7),
        Radius.circular(w * 0.03),
      ),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.28 * a),
    );

    canvas.drawRRect(
      body,
      Paint()
        ..color = const Color(0xFF1B2233).withValues(alpha: 0.55 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  // --- Colisión ---------------------------------------------------------------
  // La banda de altura y los tres pasos (fila, carril, altura) viven en
  // [DepthComponent.collidesWith]; acá no hay nada propio que agregar.
}
