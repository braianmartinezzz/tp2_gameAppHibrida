import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'depth_component.dart';
import 'perspective.dart';

/// Tipo de power-up. Los tres se agarran simplemente tocándolos: flotan a la
/// altura del suelo, así no exigen un gesto.
enum PowerUpKind {
  /// Escudo: absorbe **un golpe** y se rompe.
  shield,

  /// Imán: atrae las monedas cercanas hacia el carril del jugador.
  magnet,

  /// Multiplicador: el score sube al doble durante unos segundos.
  multiplier;

  Color get color => switch (this) {
        shield => const Color(0xFF5AA9FF),
        magnet => const Color(0xFFFF6B6B),
        multiplier => const Color(0xFFFFD166),
      };
}

/// Power-up flotante proyectado en perspectiva 2.5D (hereda la ley de
/// movimiento y la colisión de [DepthComponent]).
///
/// Flota unos px sobre el suelo (banda 4..44), por lo que la caja parada del
/// jugador lo recoge sin salto ni agachada.
class PowerUpComponent extends DepthComponent {
  PowerUpComponent({
    required this.kind,
    required super.lane,
    required super.perspective,
    required super.speed,
    required super.spawnT,
  }) : super(
          position: Vector2.zero(),
          size: Vector2.all(1),
          anchor: Anchor.topLeft,
        ) {
    syncGeometry();
  }

  /// Tamaño del ítem en unidades de la línea base (t = 1).
  static const double worldSize = 40;

  /// Altura del borde inferior sobre el suelo (lo mantiene "flotando").
  static const double bandBase = 4;

  /// Ítem a aplicar al tocarlo.
  final PowerUpKind kind;

  double _bandMinPx = 0;
  double _anim = 0;

  /// Mismo perdón lateral que las monedas (ver [CoinComponent.lateralSlack]).
  @override
  double get lateralSlack => size.x * 0.6;

  void syncGeometry() {
    final s = depthScale;
    final w = worldSize * s;
    _bandMinPx = bandBase * s;
    position.setValues(
      centerX - w * 0.5,
      baseY - (_bandMinPx + w),
    );
    size.setValues(w, w);
  }

  @override
  void update(double dt) {
    super.update(dt);
    advance(dt);
    _anim += dt;
    syncGeometry();
  }

  // --- Dibujo ----------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final a = alpha;
    if (a <= 0) return;
    final w = size.x;
    final h = size.y;

    // Sombra en el piso (sin balanceo): apoya el ítem en la ruta.
    final groundY = h + _bandMinPx;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, groundY),
        width: w * 0.7,
        height: (groundY * 0.05 + 2).clamp(2.0, 10.0),
      ),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.22 * a),
    );

    // Balanceo suave: el ítem "flota" mientras viaja.
    final bob = math.sin(_anim * 3.4) * (h * 0.07);
    canvas.save();
    canvas.translate(0, bob);
    drawBadge(canvas, kind, Rect.fromLTWH(0, 0, w, h), a);
    canvas.restore();
  }

  /// Dibuja la ficha completa (halo, cuerpo, borde y glifo) en [rect].
  ///
  /// Es la única fuente del dibujo: la usa el ítem en el corredor y el HUD de
  /// power-ups del juego, para que se vean idénticos.
  static void drawBadge(
    Canvas canvas,
    PowerUpKind kind,
    Rect rect,
    double alpha,
  ) {
    final w = rect.width;
    final h = rect.height;

    // Halo del color del power-up.
    canvas.drawCircle(
      rect.center,
      w * 0.62,
      Paint()..color = kind.color.withValues(alpha: 0.18 * alpha),
    );

    // Ficha redondeada.
    final body = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.24));
    canvas.drawRRect(
      body,
      Paint()..color = kind.color.withValues(alpha: alpha),
    );
    canvas.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (w * 0.05).clamp(1.0, 4.0)
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.9 * alpha),
    );

    canvas.save();
    canvas.translate(rect.left, rect.top);
    switch (kind) {
      case PowerUpKind.shield:
        _drawShield(canvas, w, h, alpha);
      case PowerUpKind.magnet:
        _drawMagnet(canvas, w, h, alpha);
      case PowerUpKind.multiplier:
        _drawTimesTwo(canvas, w, h, alpha);
    }
    canvas.restore();
  }

  /// Escudo: rombo redondeado con punta abajo.
  static void _drawShield(Canvas canvas, double w, double h, double a) {
    final p = Path()
      ..moveTo(w * 0.5, h * 0.28)
      ..lineTo(w * 0.7, h * 0.37)
      ..lineTo(w * 0.68, h * 0.57)
      ..quadraticBezierTo(w * 0.64, h * 0.7, w * 0.5, h * 0.76)
      ..quadraticBezierTo(w * 0.36, h * 0.7, w * 0.32, h * 0.57)
      ..lineTo(w * 0.3, h * 0.37)
      ..close();
    canvas.drawPath(p, Paint()..color = Colors.white.withValues(alpha: 0.95 * a));
  }

  /// Imán: herradura (arco + dos patas).
  static void _drawMagnet(Canvas canvas, double w, double h, double a) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromLTWH(w * 0.32, h * 0.32, w * 0.36, h * 0.36),
      math.pi,
      math.pi,
      false,
      paint,
    );
    canvas.drawLine(Offset(w * 0.32, h * 0.5), Offset(w * 0.32, h * 0.7), paint);
    canvas.drawLine(Offset(w * 0.68, h * 0.5), Offset(w * 0.68, h * 0.7), paint);
    // Polos: dos puntitas oscuras para que se lea como un imán.
    final tips = Paint()
      ..color = const Color(0xFF2B2318).withValues(alpha: 0.85 * a);
    canvas.drawLine(Offset(w * 0.32, h * 0.64), Offset(w * 0.32, h * 0.7), tips);
    canvas.drawLine(Offset(w * 0.68, h * 0.64), Offset(w * 0.68, h * 0.7), tips);
  }

  /// Multiplicador: la etiqueta "x2" dibujada con trazos.
  ///
  /// No se usa TextPainter a propósito: los previews (y cualquier render de
  /// test) corren con la fuente de relleno, donde *todo* glifo es un cuadro
  /// sólido y el signo salía como un rectángulo negro. Con trazos el glifo se
  /// lee igual en previews, tests y dispositivo.
  static void _drawTimesTwo(Canvas canvas, double w, double h, double a) {
    final paint = Paint()
      ..color = const Color(0xFF2B2318).withValues(alpha: a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.085).clamp(1.5, 5.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // "×"
    final times = Path()
      ..moveTo(w * 0.16, h * 0.35)
      ..lineTo(w * 0.34, h * 0.63)
      ..moveTo(w * 0.34, h * 0.35)
      ..lineTo(w * 0.16, h * 0.63);

    // "2": panza arriba, diagonal a la izquierda y base.
    final two = Path()
      ..moveTo(w * 0.48, h * 0.42)
      ..cubicTo(w * 0.48, h * 0.26, w * 0.86, h * 0.26, w * 0.84, h * 0.44)
      ..lineTo(w * 0.51, h * 0.63)
      ..lineTo(w * 0.88, h * 0.63);

    canvas
      ..drawPath(times, paint)
      ..drawPath(two, paint);
  }
}

/// Genera un power-up de [kind] en [lane], nacido desvanecido un poco más
/// profundo (t = 0.13) que los obstáculos (t = 0.06): así un obstáculo que
/// aparezca después queda lejos de entrada y la distancia solo crece (ver
/// [buildCoinPattern] para el detalle de la regla).
PowerUpComponent buildPowerUp({
  required PowerUpKind kind,
  required Perspective perspective,
  required double speed,
  required double lane,
  double spawnT = 0.13,
}) =>
    PowerUpComponent(
      kind: kind,
      lane: lane.clamp(-1.0, 1.0),
      perspective: perspective,
      speed: speed,
      spawnT: spawnT,
    );
