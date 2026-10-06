import 'dart:math';

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

  /// Auto abandonado que **ocupa dos carriles** (banda 0..72, más alto que el
  /// techo del salto): hay que irse al carril libre. Se genera centrado en
  /// -0.5 (cubre los carriles -1 y 0) o en +0.5 (cubre 0 y +1).
  car,
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

  static const Color _ink = Color(0xFF1B1A17);
  static const Color _rustColor = Color(0xFF8B4A1E);

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
        // Ancho en función del corredor (no en px fijos): 0.66 de baseWidth =
        // 1.32 unidades de carril, o sea dos carriles completos con el margen
        // justo para que el jugador parado en el segundo también choque.
        ObstacleKind.car => (
          width: perspective.baseWidth * carWidthFrac,
          bandMin: 0,
          bandMax: 72,
        ),
      };

  /// Fracción de `baseWidth` que ocupa un auto de dos carriles.
  static const double carWidthFrac = 0.66;

  /// Carriles (-1, 0, 1) que bloquea este obstáculo.
  List<double> get coveredLanes => kind == ObstacleKind.car
      ? (lane > 0 ? const [0.0, 1.0] : const [-1.0, 0.0])
      : [lane.roundToDouble()];

  bool coversLane(double l) => coveredLanes.contains(l);

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
      case ObstacleKind.car:
        _drawCar(canvas, w, h);
    }
  }

  /// Mancha de óxido: óvalo marrón anaranjado, translúcido.
  void _rust(Canvas canvas, Rect r, double a, {double opacity = 0.35}) {
    canvas.drawOval(
      r,
      Paint()..color = _rustColor.withValues(alpha: opacity * a),
    );
  }

  /// Barrera de concreto agrietada con restos de cinta de peligro y alambre
  /// de púas encima (se salta).
  void _drawBarrier(Canvas canvas, double w, double h) {
    final a = alpha;
    final rect = Rect.fromLTWH(0, 0, w, h);
    final body = Path()
      ..moveTo(w * 0.02, h)
      ..lineTo(w * 0.12, h * 0.05)
      ..lineTo(w * 0.88, h * 0.05)
      ..lineTo(w * 0.98, h)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFFA7A398).withValues(alpha: a),
            const Color(0xFF55524B).withValues(alpha: a),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipPath(body);
    // Franjas de peligro desteñidas en la parte alta.
    final stripe = Paint()
      ..color = const Color(0xFFB8963A).withValues(alpha: 0.75 * a);
    final step = max(4.0, w / 7);
    final bandBottom = h * 0.55;
    for (var x = -h; x < w + h; x += step * 2) {
      canvas.drawPath(
        Path()
          ..moveTo(x, bandBottom)
          ..lineTo(x + step, bandBottom)
          ..lineTo(x + step + bandBottom, 0)
          ..lineTo(x + bandBottom, 0)
          ..close(),
        stripe,
      );
    }
    // Mugre acumulada abajo y una mancha de óxido.
    canvas.drawRect(
      Rect.fromLTWH(0, h * 0.62, w, h * 0.38),
      Paint()..color = _ink.withValues(alpha: 0.30 * a),
    );
    _rust(canvas, Rect.fromLTWH(w * 0.55, h * 0.4, w * 0.3, h * 0.35), a);
    canvas.restore();

    // Grieta en el concreto.
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.36, h * 0.05)
        ..lineTo(w * 0.42, h * 0.38)
        ..lineTo(w * 0.35, h * 0.62)
        ..lineTo(w * 0.40, h),
      Paint()
        ..color = _ink.withValues(alpha: 0.65 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, w * 0.012),
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = _ink.withValues(alpha: 0.6 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Alambre de púas enrollado sobre el borde superior.
    final wire = Paint()
      ..color = const Color(0xFF26231F).withValues(alpha: 0.9 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w * 0.02);
    final wy = -h * 0.28;
    const waves = 8;
    final coil = Path()..moveTo(w * 0.06, wy);
    for (var i = 0; i < waves; i++) {
      final x1 = w * (0.06 + 0.88 * (i + 1) / waves);
      final x0 = w * (0.06 + 0.88 * i / waves);
      coil.quadraticBezierTo(
        (x0 + x1) * 0.5,
        wy + (i.isEven ? -h * 0.5 : h * 0.5),
        x1,
        wy,
      );
    }
    canvas.drawPath(coil, wire);
    final barb = max(1.0, w * 0.025);
    for (var i = 1; i < waves; i++) {
      final x = w * (0.06 + 0.88 * i / waves);
      canvas.drawLine(Offset(x - barb, wy - barb), Offset(x + barb, wy + barb), wire);
      canvas.drawLine(Offset(x - barb, wy + barb), Offset(x + barb, wy - barb), wire);
    }
    for (final fx in const [0.1, 0.9]) {
      canvas.drawLine(Offset(w * fx, wy), Offset(w * fx, h * 0.08), wire);
    }
  }

  /// Chapa de acero oxidada y agujereada, en alto sobre dos postes
  /// retorcidos (hay que agacharse).
  void _drawOverhead(Canvas canvas, double w, double h, double groundY) {
    final a = alpha;

    // Postes torcidos que la sostienen (a los costados: se pasa por debajo).
    final post = Paint()
      ..color = const Color(0xFF2A2724).withValues(alpha: a)
      ..strokeWidth = max(2.0, w * 0.09)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.08, h), Offset(w * 0.03, groundY), post);
    canvas.drawLine(Offset(w * 0.92, h), Offset(w * 0.98, groundY), post);

    // Cables cortados que cuelgan del borde inferior.
    final cable = Paint()
      ..color = _ink.withValues(alpha: 0.85 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w * 0.025);
    final drop = (groundY - h) * 0.35;
    for (final (fx, bend) in const [(0.3, 0.05), (0.68, -0.06)]) {
      canvas.drawPath(
        Path()
          ..moveTo(w * fx, h)
          ..quadraticBezierTo(
            w * (fx + bend),
            h + drop * 0.6,
            w * (fx + bend * 0.4),
            h + drop,
          ),
        cable,
      );
    }

    final rect = Rect.fromLTWH(0, 0, w, h);
    // Panel con el borde superior desgarrado.
    final panel = Path()
      ..moveTo(0, h * 0.04)
      ..lineTo(w * 0.3, 0)
      ..lineTo(w * 0.46, h * 0.035)
      ..lineTo(w * 0.7, h * 0.005)
      ..lineTo(w, h * 0.03)
      ..lineTo(w * 0.98, h)
      ..lineTo(w * 0.02, h)
      ..close();
    canvas.drawPath(
      panel,
      Paint()
        ..shader = LinearGradient(
          colors: [
            const Color(0xFF626B73).withValues(alpha: a),
            const Color(0xFF2F3439).withValues(alpha: a),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipPath(panel);
    // Óxido en las esquinas y chorreras.
    _rust(canvas, Rect.fromLTWH(-w * 0.1, h * 0.55, w * 0.7, h * 0.5), a, opacity: 0.45);
    _rust(canvas, Rect.fromLTWH(w * 0.55, -h * 0.1, w * 0.6, h * 0.35), a, opacity: 0.4);
    final streak = Paint()
      ..color = _rustColor.withValues(alpha: 0.4 * a)
      ..strokeWidth = max(1.0, w * 0.04);
    for (final fx in const [0.2, 0.52, 0.8]) {
      canvas.drawLine(Offset(w * fx, h * 0.1), Offset(w * fx, h * (0.45 + fx * 0.4)), streak);
    }
    // Franjas de peligro casi borradas en el borde inferior.
    final hazard = Paint()
      ..color = const Color(0xFFB8963A).withValues(alpha: 0.5 * a);
    final bandTop = h * 0.84;
    final step = w / 4.0;
    for (var i = -2; i < 7; i++) {
      final x = i * step;
      canvas.drawPath(
        Path()
          ..moveTo(x, h)
          ..lineTo(x + step * 0.5, h)
          ..lineTo(x + step * 0.5 + (h - bandTop), bandTop)
          ..lineTo(x + (h - bandTop), bandTop)
          ..close(),
        hazard,
      );
    }
    // Una X de aerosol rojo, a medio borrar.
    final spray = Paint()
      ..color = const Color(0xFF8C1C1C).withValues(alpha: 0.6 * a)
      ..strokeWidth = max(2.0, w * 0.09)
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * 0.28, h * 0.22), Offset(w * 0.72, h * 0.68), spray);
    canvas.drawLine(Offset(w * 0.72, h * 0.2), Offset(w * 0.3, h * 0.7), spray);
    // Agujeros de bala.
    for (final (fx, fy) in const [(0.18, 0.3), (0.82, 0.42), (0.62, 0.15)]) {
      final c = Offset(w * fx, h * fy);
      final r = max(1.2, w * 0.035);
      canvas.drawCircle(c, r * 1.6, Paint()..color = _ink.withValues(alpha: 0.25 * a));
      canvas.drawCircle(c, r, Paint()..color = _ink.withValues(alpha: 0.9 * a));
    }
    canvas.restore();

    // Remaches en los bordes.
    final rivet = Paint()..color = _ink.withValues(alpha: 0.55 * a);
    final rr = max(1.0, w * 0.02);
    for (var i = 0; i < 5; i++) {
      final y = h * (0.12 + 0.19 * i);
      canvas.drawCircle(Offset(w * 0.06, y), rr, rivet);
      canvas.drawCircle(Offset(w * 0.94, y), rr, rivet);
    }
    canvas.drawPath(
      panel,
      Paint()
        ..color = _ink.withValues(alpha: 0.65 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  /// Dos contenedores de carga apilados, oxidados y abollados (hay que
  /// esquivarlos de carril).
  void _drawBlock(Canvas canvas, double w, double h) {
    final a = alpha;
    final gap = max(1.0, h * 0.012);
    final half = (h - gap) * 0.5;
    // El de arriba, más chico y corrido, como si lo hubieran tirado encima.
    final top = Rect.fromLTWH(w * 0.04, 0, w * 0.92, half);
    final bottom = Rect.fromLTWH(0, half + gap, w, half);
    _drawContainer(canvas, bottom, const Color(0xFF7D3B2E), a, smear: true);
    _drawContainer(canvas, top, const Color(0xFF3F5B57), a);
  }

  /// Un contenedor visto de frente: chapa corrugada, puertas con barras,
  /// óxido y marco oscuro.
  void _drawContainer(
    Canvas canvas,
    Rect r,
    Color base,
    double a, {
    bool smear = false,
  }) {
    final dark = Color.lerp(base, Colors.black, 0.5)!;
    final light = Color.lerp(base, Colors.white, 0.12)!;
    final frame = RRect.fromRectAndRadius(
      r,
      Radius.circular(max(1.0, r.width * 0.04)),
    );
    canvas.drawRRect(
      frame,
      Paint()
        ..shader = LinearGradient(
          colors: [
            light.withValues(alpha: a),
            base.withValues(alpha: a),
            dark.withValues(alpha: a),
          ],
          stops: const [0.0, 0.45, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(r),
    );

    // Corrugado vertical.
    final rib = Paint()
      ..color = dark.withValues(alpha: 0.45 * a)
      ..strokeWidth = max(0.8, r.width * 0.025);
    const ribs = 9;
    for (var i = 1; i < ribs; i++) {
      final x = r.left + r.width * i / ribs;
      canvas.drawLine(
        Offset(x, r.top + r.height * 0.07),
        Offset(x, r.bottom - r.height * 0.07),
        rib,
      );
    }

    // Óxido y chorreras.
    _rust(
      canvas,
      Rect.fromLTWH(r.left + r.width * 0.08, r.bottom - r.height * 0.38,
          r.width * 0.4, r.height * 0.3),
      a,
    );
    _rust(
      canvas,
      Rect.fromLTWH(r.left + r.width * 0.6, r.top + r.height * 0.05,
          r.width * 0.3, r.height * 0.22),
      a,
      opacity: 0.28,
    );

    if (smear) {
      // Manchas oscuras que chorrean: nadie usó esto como escondite.
      final blood = Paint()
        ..color = const Color(0xFF4A0E0E).withValues(alpha: 0.55 * a)
        ..strokeWidth = max(1.0, r.width * 0.05)
        ..strokeCap = StrokeCap.round;
      for (final (fx, len) in const [(0.28, 0.5), (0.34, 0.3), (0.7, 0.42)]) {
        canvas.drawLine(
          Offset(r.left + r.width * fx, r.top + r.height * 0.2),
          Offset(r.left + r.width * fx, r.top + r.height * (0.2 + len)),
          blood,
        );
      }
    }

    // Barras y manijas de las puertas.
    final bar = Paint()
      ..color = _ink.withValues(alpha: 0.7 * a)
      ..strokeWidth = max(1.0, r.width * 0.05)
      ..strokeCap = StrokeCap.round;
    for (final fx in const [0.4, 0.6]) {
      canvas.drawLine(
        Offset(r.left + r.width * fx, r.top + r.height * 0.14),
        Offset(r.left + r.width * fx, r.bottom - r.height * 0.14),
        bar,
      );
    }
    final handle = Paint()
      ..color = const Color(0xFFB9B2A4).withValues(alpha: 0.7 * a)
      ..strokeWidth = max(1.0, r.width * 0.035)
      ..strokeCap = StrokeCap.round;
    for (final fx in const [0.37, 0.63]) {
      canvas.drawLine(
        Offset(r.left + r.width * fx, r.center.dy - r.height * 0.06),
        Offset(r.left + r.width * fx, r.center.dy + r.height * 0.06),
        handle,
      );
    }

    // Marco oscuro.
    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r.width * 0.05)
        ..color = dark.withValues(alpha: 0.85 * a),
    );
  }

  /// Auto abandonado **atravesado** en la ruta, visto de costado. Ocupa dos
  /// carriles, o sea que su caja mide ~3:1: una trasera dibujada en ese
  /// rectángulo salía achatada y estirada, pero un auto de perfil mide
  /// justamente 3:1. De paso explica por qué bloquea dos carriles.
  ///
  /// Mira hacia afuera de la ruta: el del carril izquierdo apunta a la
  /// izquierda y el del derecho, a la derecha.
  void _drawCar(Canvas canvas, double w, double h) {
    final a = alpha;
    const bodyC = Color(0xFF6B7A86);
    const glassC = Color(0xFF1B2A33);
    final light = Color.lerp(bodyC, Colors.white, 0.22)!;
    final dark = Color.lerp(bodyC, Colors.black, 0.55)!;
    final line = max(1.0, h * 0.028);

    canvas.save();
    if (lane < 0) {
      canvas.translate(w, 0);
      canvas.scale(-1, 1); // espejo: el frente queda a la izquierda
    }

    // Ruedas: centro a la altura del radio, apoyadas en el piso (h).
    final r = h * 0.19;
    final wy = h - r;
    final rearX = w * 0.21;
    final frontX = w * 0.77;

    // Silueta del sedán (frente a la derecha).
    final shell = Path()
      ..moveTo(w * 0.02, h * 0.80)
      ..lineTo(w * 0.015, h * 0.52)
      ..quadraticBezierTo(w * 0.015, h * 0.45, w * 0.07, h * 0.44)
      ..lineTo(w * 0.23, h * 0.42)
      ..lineTo(w * 0.31, h * 0.10)
      ..quadraticBezierTo(w * 0.32, h * 0.07, w * 0.36, h * 0.07)
      ..lineTo(w * 0.58, h * 0.07)
      ..quadraticBezierTo(w * 0.62, h * 0.07, w * 0.65, h * 0.11)
      ..lineTo(w * 0.74, h * 0.42)
      ..lineTo(w * 0.93, h * 0.47)
      ..quadraticBezierTo(w * 0.985, h * 0.50, w * 0.985, h * 0.58)
      ..lineTo(w * 0.985, h * 0.80)
      ..close();

    // Carrocería con degradé vertical (luz arriba, sombra abajo).
    canvas.drawPath(
      shell,
      Paint()
        ..shader = LinearGradient(
          colors: [
            light.withValues(alpha: a),
            bodyC.withValues(alpha: a),
            dark.withValues(alpha: a),
          ],
          stops: const [0.0, 0.5, 1.0],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Pasarruedas oscuros (recortados a la carrocería).
    canvas.save();
    canvas.clipPath(shell);
    for (final x in [rearX, frontX]) {
      canvas.drawCircle(
        Offset(x, wy),
        r * 1.28,
        Paint()..color = _ink.withValues(alpha: 0.85 * a),
      );
    }
    canvas.restore();

    // Paragolpes.
    final bumper = Paint()..color = dark.withValues(alpha: a);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.70, w * 0.07, h * 0.10), bumper);
    canvas.drawRect(
        Rect.fromLTWH(w * 0.93, h * 0.70, w * 0.07, h * 0.10), bumper);

    // Vidrios: trasero (con grieta) y delantero.
    final rearGlass = Path()
      ..moveTo(w * 0.27, h * 0.40)
      ..lineTo(w * 0.335, h * 0.15)
      ..lineTo(w * 0.425, h * 0.15)
      ..lineTo(w * 0.425, h * 0.40)
      ..close();
    final frontGlass = Path()
      ..moveTo(w * 0.465, h * 0.40)
      ..lineTo(w * 0.465, h * 0.15)
      ..lineTo(w * 0.60, h * 0.15)
      ..lineTo(w * 0.70, h * 0.40)
      ..close();
    final glassPaint = Paint()..color = glassC.withValues(alpha: 0.92 * a);
    canvas.drawPath(rearGlass, glassPaint);
    canvas.drawPath(frontGlass, glassPaint);
    final shine = Paint()
      ..color = const Color(0xFFCFE3EA).withValues(alpha: 0.35 * a)
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.8, h * 0.03);
    canvas.drawLine(Offset(w * 0.50, h * 0.37), Offset(w * 0.56, h * 0.18), shine);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.38, h * 0.15)
        ..lineTo(w * 0.35, h * 0.26)
        ..lineTo(w * 0.40, h * 0.31)
        ..lineTo(w * 0.36, h * 0.40),
      shine..color = const Color(0xFFCFE3EA).withValues(alpha: 0.7 * a),
    );

    // Puertas, cintura y manijas.
    final seam = Paint()
      ..color = _ink.withValues(alpha: 0.55 * a)
      ..strokeWidth = line * 0.8;
    canvas.drawLine(Offset(w * 0.445, h * 0.15), Offset(w * 0.445, h * 0.76), seam);
    canvas.drawLine(Offset(w * 0.255, h * 0.44), Offset(w * 0.255, h * 0.76), seam);
    canvas.drawLine(Offset(w * 0.69, h * 0.44), Offset(w * 0.69, h * 0.76), seam);
    canvas.drawLine(
      Offset(w * 0.05, h * 0.50),
      Offset(w * 0.95, h * 0.50),
      Paint()
        ..color = light.withValues(alpha: 0.35 * a)
        ..strokeWidth = line * 0.8,
    );
    final handle = Paint()..color = light.withValues(alpha: 0.8 * a);
    canvas.drawRect(Rect.fromLTWH(w * 0.395, h * 0.53, w * 0.035, h * 0.04), handle);
    canvas.drawRect(Rect.fromLTWH(w * 0.635, h * 0.53, w * 0.035, h * 0.04), handle);

    // Luces: trasera apagada y delantera rota.
    canvas.drawRect(
      Rect.fromLTWH(w * 0.012, h * 0.52, w * 0.04, h * 0.07),
      Paint()..color = const Color(0xFF7A1C17).withValues(alpha: a),
    );
    canvas.drawRect(
      Rect.fromLTWH(w * 0.945, h * 0.53, w * 0.04, h * 0.06),
      Paint()..color = const Color(0xFFB8B49A).withValues(alpha: 0.9 * a),
    );

    // Óxido en puerta, baúl y capó.
    _rust(canvas, Rect.fromLTWH(w * 0.46, h * 0.52, w * 0.20, h * 0.24), a);
    _rust(canvas, Rect.fromLTWH(w * 0.06, h * 0.50, w * 0.14, h * 0.18), a,
        opacity: 0.28);
    _rust(canvas, Rect.fromLTWH(w * 0.78, h * 0.46, w * 0.14, h * 0.10), a,
        opacity: 0.30);

    // Contorno.
    canvas.drawPath(
      shell,
      Paint()
        ..color = _ink.withValues(alpha: 0.75 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = line
        ..strokeJoin = StrokeJoin.round,
    );

    // Ruedas. La trasera está pinchada (aplastada) y se le ve la llanta.
    void wheel(double x, {bool flat = false}) {
      final ry = flat ? r * 0.78 : r;
      final cy = h - ry;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, cy), width: r * 2, height: ry * 2),
        Paint()..color = _ink.withValues(alpha: a),
      );
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(x, cy), width: r * 1.1, height: ry * 1.1),
        Paint()..color = const Color(0xFF8C8A84).withValues(alpha: a),
      );
      canvas.drawCircle(
        Offset(x, cy),
        r * 0.24,
        Paint()..color = const Color(0xFF3A3834).withValues(alpha: a),
      );
    }

    wheel(rearX, flat: true);
    wheel(frontX);

    canvas.restore();
  }

  // --- Colisión ---------------------------------------------------------------
  // La banda de altura y los tres pasos (fila, carril, altura) viven en
  // [DepthComponent.collidesWith]; acá no hay nada propio que agregar.
}
