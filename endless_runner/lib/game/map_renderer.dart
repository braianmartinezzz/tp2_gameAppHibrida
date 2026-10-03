import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'perspective.dart';

/// Dibuja el mapa 2.5D del corredor en ambiente 🏜️ desierto / carretera:
///
///  1. cielo con gradiente, estrellas y luna (de noche) o sol (de día),
///  2. nubes a la deriva,
///  3. capas de parallax (mesetas lejanas y dunas cercanas) ancladas al
///     horizonte, con "guiñada" según la posición del jugador,
///  4. arena fuera de la ruta y hombro de grava,
///  5. asfalto en perspectiva con marcas viales: divisores de carril
///     punteados (en coordenada de mundo: se comprimen solos hacia el
///     horizonte y aceleran al acercarse), líneas de borde y bandas de
///     velocidad,
///  6. **props de desierto** (cactus, rocas, arbustos, mesetas y carteles)
///     que pasan a izquierda y derecha en la misma coordenada de mundo que
///     el asfalto (sensación de carretera en movimiento),
///  7. bruma de distancia que suaviza el horizonte.
///
/// Mantiene su propio estado de animación (tiempo, profundidad de rayas,
/// manchones y props) para que el mapa avance incluso sin obstáculos.
class MapRenderer {
  MapRenderer() {
    _props.addAll(_seedProps());
    _sortPropsFarToNear();
    // Campo de estrellas determinista: mismas estrellas en cada corrida.
    final rnd = Random(7);
    _stars.addAll(
      List<Offset>.generate(
        64,
        (_) => Offset(rnd.nextDouble(), rnd.nextDouble() * 0.9),
      ),
    );
  }

  // --- Geometría de la carretera --------------------------------------------
  /// Ancho extra del asfalto hacia afuera de la ruta de juego (fracción del
  /// ancho del corredor). La carretera es más ancha que los carriles para
  /// que el corredor de la banda externa no salga corriendo por la arena.
  static const double roadExtraFrac = 0.07;

  /// Hombro de grava entre el asfalto y la arena (misma fracción).
  static const double shoulderFrac = 0.045;

  // --- Props del desierto ----------------------------------------------------
  /// Cantidad de props por lado de la carretera. La densidad media con
  /// huecos es deliberada: tiene que verse el fondo entre prop y prop para
  /// que cada uno se lea como algo que pasa, no como una muralla.
  static const int _propCount = 7;

  /// Profundidad mínima de un prop (1 = línea base de la carretera).
  static const double _propZMin = 1.0;

  /// Recorrido total de cada lado: al superar `_propZMin` el prop se recicla
  /// al fondo (`z += _propSpan`), sin asignaciones.
  static const double _propSpan = 3.0;

  static const double _propZStep = _propSpan / _propCount;

  /// z a partir de la cual el prop está totalmente sólido / se disuelve.
  static const double _propFadeInZ = 3.2;
  static const double _propFadeOutZ = 3.98;

  /// Tipos de prop (`style % _kindCount`): cactus, roca, arbusto seco,
  /// meseta y cartel de ruta.
  static const int _kindCount = 5;

  /// Tipo por posición en la carretera: alterna siluetas a lo largo del
  /// recorrido y los dos lados arrancan en puntos distintos del patrón.
  static const List<int> _kindByIndex = [0, 3, 1, 4, 2, 0, 3];

  /// Ancho del rectángulo base por tipo (sobre el ancho del corredor).
  static const List<double> _kindWidthFrac = [0.16, 0.34, 0.30, 0.46, 0.20];

  /// Alto por tipo (sobre la altura de la pantalla): la meseta manda y el
  /// arbusto se queda bajo.
  static const List<double> _kindHeightFrac = [0.92, 0.40, 0.32, 1.12, 0.86];

  /// Separación extra desde el hueco mínimo por tipo: el cartel pega a la
  /// ruta y la meseta se queda más atrás.
  static const List<double> _kindLateral = [0.2, 0.5, 0.7, 0.35, 0.0];

  /// Props vivos, ordenados de lejos a cerca (se reordena al reciclar).
  final List<SideProp> _props = [];

  /// Props costados vigentes, de lejos a cerca.
  @visibleForTesting
  List<SideProp> get props => _props;

  /// Existe solo para los tests de look: apaga el dibujo de los props y deja
  /// la arena limpia para medirla píxel a píxel.
  @visibleForTesting
  bool drawProps = true;

  List<SideProp> _seedProps() {
    final list = <SideProp>[];
    for (final side in const [-1, 1]) {
      for (var i = 0; i < _propCount; i++) {
        // El lado derecho va desfasado medio paso: los dos no se espejan.
        final k = i + (side > 0 ? 0.5 : 0.0);
        final kind =
            _kindByIndex[(i + (side > 0 ? 3 : 0)) % _kindByIndex.length];
        list.add(
          SideProp(
            side: side,
            z: _propZMin + k * _propZStep,
            widthFrac: _kindWidthFrac[kind],
            heightFrac: _kindHeightFrac[kind],
            lateralFrac: _kindLateral[kind],
            // `style % _kindCount` es el tipo; el resto de la semilla varía
            // el tono entre props del mismo tipo.
            style: i * _kindCount + kind,
          ),
        );
      }
    }
    return list;
  }

  void _sortPropsFarToNear() {
    // z grande = lejos → se dibuja primero para que los cercanos queden encima.
    _props.sort((a, b) => b.z.compareTo(a.z));
  }

  // --- Rayas de velocidad ----------------------------------------------------
  // Coordenada de mundo `z`: 1 = línea base, > 1 = más lejos. Avanzan
  // uniformemente en `z` (velocidad de mundo constante), lo que en pantalla
  // se traduce en la compresión perspectiva clásica.
  static const int _stripeCount = 10;
  static const double _stripeZMin = 1.0;
  static const double _stripeZStep = 0.4;
  static const double _stripeSpan = _stripeCount * _stripeZStep;

  final List<double> _stripes = List<double>.generate(
    _stripeCount,
    (i) => _stripeZMin + i * _stripeZStep,
  );

  // --- Divisores de carril ---------------------------------------------------
  /// Patrón punteado en coordenada de mundo: período y largo de cada manchón
  /// (el período más el hueco es lo que hace leer la línea discontinua).
  static const double _dashPeriod = 0.5;
  static const double _dashLen = 0.3;
  static const double _dashZMin = 1.0;
  static const double _dashZMax = 5.0;

  /// Avance del patrón en z (misma unidad que las rayas y los props).
  double _dashPhase = 0;

  double _time = 0;

  final List<Offset> _stars = [];

  // --- Capas de parallax -----------------------------------------------------
  /// Silueta de mesetas/buttes de la capa lejana (planos, con huecos).
  static const List<double> _mesas = [0.55, 0.9, 0.4, 0.75, 1.0, 0.62];

  /// Perfil redondeado de las dunas de la capa cercana.
  static const List<double> _dunes = [0.6, 0.95, 0.45, 0.8, 1.0, 0.5];

  static const List<({double x0, double yFrac, double scale, double speed})>
      _clouds = [
    (x0: 40.0, yFrac: 0.42, scale: 1.0, speed: 3.0),
    (x0: 260.0, yFrac: 0.25, scale: 0.7, speed: 2.2),
    (x0: 430.0, yFrac: 0.58, scale: 1.2, speed: 4.0),
  ];

  /// Avanza la animación del mapa. [worldSpeed] es la velocidad del juego en
  /// px/s sobre la línea base: rayas, manchones y props usan la misma
  /// unidad, así que la carretera acelera entera con la dificultad.
  void update(double dt, double worldSpeed, Perspective p) {
    _time += dt;
    if (p.corridorHeight <= 0) return;
    // En la línea base (z = 1) el avance en z equivale exactamente a
    // `worldSpeed` px/s en pantalla.
    final dz = (worldSpeed / p.corridorHeight) * dt;
    if (dz <= 0) return;
    for (var i = 0; i < _stripes.length; i++) {
      var z = _stripes[i] - dz;
      while (z < _stripeZMin) {
        z += _stripeSpan;
      }
      _stripes[i] = z;
    }

    // Los props avanzan con el MISMO dz que el asfalto: la orilla se mueve a
    // la velocidad exacta del juego y acelera con la dificultad.
    var reordered = false;
    for (final prop in _props) {
      var z = prop.z - dz;
      while (z < _propZMin) {
        z += _propSpan;
      }
      if (z > prop.z) reordered = true; // dio la vuelta: va al fondo
      prop.z = z;
    }
    if (reordered) _sortPropsFarToNear();

    // El punteado de las divisorias corre en z con la misma velocidad.
    _dashPhase = _wrap(_dashPhase - dz, _dashPeriod);
  }

  /// Mantiene [value] en [0, mod) (módulo siempre positivo).
  static double _wrap(double value, double mod) => ((value % mod) + mod) % mod;

  void render(
    Canvas canvas,
    Perspective p, {
    required bool dark,
    required double playerX,
  }) {
    if (p.width <= 0 || p.height <= 0) return;
    final c = dark ? _dark : _light;
    final w = p.width;
    final h = p.height;
    final vx = p.vanishX;
    final vy = p.vanishY;

    // 1) Cielo ---------------------------------------------------------------
    // El rect baja 1 px de más: si el cielo y la arena se tocaran justo en
    // `vy` (que casi nunca cae redondo en un píxel) quedaría una fila de
    // borde antialias con alfa incompleto.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, vy + 1),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 0),
          Offset(0, vy),
          [c.skyTop, c.skyBottom],
        ),
    );

    // Guiñada del fondo según la posición del jugador (parallax de cámara).
    final sway = -(playerX - vx);

    // 2) Estrellas (solo de noche) --------------------------------------------
    if (c.night) {
      for (final star in _stars) {
        final tw = 0.4 + 0.4 * sin(_time * 2.2 + star.dx * 47);
        canvas.drawCircle(
          Offset(star.dx * w, star.dy * vy),
          1.0 + star.dy * 0.6,
          Paint()..color = c.star.withValues(alpha: tw),
        );
      }
    }

    // 3) Luna o sol, con su halo ------------------------------------------------
    _drawCelestialBody(canvas, w: w, vy: vy, c: c);

    // 4) Nubes ----------------------------------------------------------------
    _drawClouds(
      canvas,
      w: w,
      baseY: vy,
      paint: Paint()..color = c.cloud,
      sway: sway,
    );

    // 5) Capas de parallax: mesetas lejanas, dunas cercanas ---------------------
    _drawMesas(
      canvas,
      w: w,
      baseY: vy,
      period: 132,
      offset: _time * 4 + sway * 0.05,
      heights: _mesas,
      maxHeight: vy * 0.62,
      paint: Paint()..color = c.ridgeFar,
      rim: Paint()
        ..color = c.ridgeLit.withValues(alpha: 0.75)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    _drawBumps(
      canvas,
      w: w,
      baseY: vy,
      period: 168,
      offset: _time * 9 + sway * 0.08,
      heights: _dunes,
      maxHeight: vy * 0.34,
      paint: Paint()..color = c.duneNear,
    );

    // Diferenciación más clara del horizonte para reforzar el desierto.
    canvas.drawRect(
      Rect.fromLTWH(0, vy * 0.82, w, vy * 0.28),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, vy * 0.82),
          Offset(0, vy + vy * 0.28),
          [
            c.haze.withValues(alpha: 0.18),
            c.haze.withValues(alpha: 0.0),
          ],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, vy - 4, w, 8),
      Paint()..color = c.ridgeLit.withValues(alpha: 0.12),
    );

    // 6) Arena fuera de la ruta -------------------------------------------------
    canvas.drawRect(
      Rect.fromLTWH(0, vy, w, h - vy),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, vy),
          Offset(0, h),
          [c.sandFar, c.sandNear],
        ),
    );

    // 7) Hombro de grava + asfalto ----------------------------------------------
    final extra = p.baseWidth * roadExtraFrac;
    final shoulderW = p.baseWidth * shoulderFrac;
    final roadPath = Path()
      ..moveTo(p.baseLeftX - extra, h)
      ..lineTo(p.baseRightX + extra, h)
      ..lineTo(vx, vy) // la carretera converge al punto de fuga
      ..close();
    canvas.drawPath(
      Path()
        ..moveTo(p.baseLeftX - extra - shoulderW, h)
        ..lineTo(p.baseRightX + extra + shoulderW, h)
        ..lineTo(vx, vy)
        ..close(),
      Paint()..color = c.shoulder,
    );
    canvas.drawPath(
      roadPath,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, vy),
          Offset(0, h),
          [c.roadFar, c.roadNear],
        ),
    );

    // 8) Marcas viales (recortadas al asfalto) -----------------------------------
    canvas.save();
    canvas.clipPath(roadPath);

    // Bandas de velocidad en coordenada de mundo: lo que hace leer la marcha.
    final stripePaint = Paint();
    for (final z in _stripes) {
      final t = 1.0 / z; // z >= 1 → t en (0, 1]
      final thickness = 1.5 + 4.5 * t;
      stripePaint.color = c.stripe.withValues(alpha: 0.06 + 0.14 * t);
      canvas.drawRect(
        Rect.fromLTWH(0, p.yAtT(t) - thickness * 0.5, w, thickness),
        stripePaint,
      );
    }

    // Divisores de carril punteados (los carriles de juego van en ±1 y 0,
    // así que las líneas caen exactamente en medio de cada carril).
    for (final lane in const [-0.5, 0.5]) {
      _drawLaneDashes(canvas, p, lane, c);
    }

    // Líneas de borde del asfalto (más ancho que la ruta: van en ±1.14).
    for (final lane in const [-1.0, 1.0]) {
      _drawLaneSegment(
        canvas,
        p,
        lane * (1 + 2 * roadExtraFrac),
        zNear: _dashZMin,
        zFar: 8.0,
        widthBase: 4.5,
        color: c.roadLine,
        alpha: 0.9,
      );
    }
    canvas.restore();

    // 9) Props de desierto (lejos primero: los cercanos pisan a los lejanos) ---
    _drawProps(canvas, p, c, sway: sway);

    // 10) Bruma de distancia + resplandor del horizonte --------------------------
    canvas.drawRect(
      Rect.fromLTWH(0, vy, w, p.corridorHeight * 0.45),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, vy),
          Offset(0, vy + p.corridorHeight * 0.45),
          [c.haze.withValues(alpha: 0.95), c.haze.withValues(alpha: 0.0)],
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, vy - 16, w, 32),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, vy - 16),
          Offset(0, vy + 16),
          [
            c.haze.withValues(alpha: 0.0),
            c.haze.withValues(alpha: 0.55),
            c.haze.withValues(alpha: 0.0),
          ],
          [0.0, 0.5, 1.0],
        ),
    );
  }

  // --- Primitivas de dibujo --------------------------------------------------

  void _drawCelestialBody(
    Canvas canvas, {
    required double w,
    required double vy,
    required _Palette c,
  }) {
    final cx = c.night ? w * 0.24 : w * 0.76;
    final cy = vy * (c.night ? 0.44 : 0.54);
    final r = c.night ? 15.0 : 28.0;
    // Halo: de noche tibio pero apagado, de día potente.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 3.4,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          r * 3.4,
          [
            c.bodyGlow.withValues(alpha: c.night ? 0.35 : 0.5),
            c.bodyGlow.withValues(alpha: 0.0),
          ],
        ),
    );
    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = c.body);
    if (c.night) {
      // Dos cráteres para que se lea luna y no sol apagado.
      canvas.drawCircle(
        Offset(cx - r * 0.3, cy - r * 0.2),
        r * 0.22,
        Paint()..color = c.bodyShade,
      );
      canvas.drawCircle(
        Offset(cx + r * 0.28, cy + r * 0.3),
        r * 0.15,
        Paint()..color = c.bodyShade,
      );
    }
  }

  void _drawClouds(
    Canvas canvas, {
    required double w,
    required double baseY,
    required Paint paint,
    required double sway,
  }) {
    final span = w + 240;
    for (final cloud in _clouds) {
      final raw = cloud.x0 + _time * cloud.speed + sway * 0.03;
      final x = ((raw % span) + span) % span - 120;
      final y = cloud.yFrac * baseY;
      final s = cloud.scale;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, y), width: 64 * s, height: 18 * s),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x - 20 * s, y + 5 * s),
          width: 40 * s,
          height: 14 * s,
        ),
        paint,
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x + 22 * s, y + 4 * s),
          width: 44 * s,
          height: 15 * s,
        ),
        paint,
      );
    }
  }

  /// Dunas: lomos redondeados que se desplazan despacio sobre el horizonte.
  void _drawBumps(
    Canvas canvas, {
    required double w,
    required double baseY,
    required double period,
    required double offset,
    required List<double> heights,
    required double maxHeight,
    required Paint paint,
  }) {
    final count = heights.length;
    final first = (offset / period).floor() - 1;
    final slots = (w / period).ceil() + 3;
    for (var i = 0; i < slots; i++) {
      final k = first + i;
      final x = k * period - offset;
      final hgt = heights[((k % count) + count) % count] * maxHeight;
      final path = Path()
        ..moveTo(x, baseY)
        // El vértice de la bézier queda en baseY - hgt.
        ..quadraticBezierTo(
            x + period * 0.5, baseY - hgt * 2, x + period, baseY)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  /// Mesetas lejanas: planchas planas con huecos y una solapa iluminada en
  /// el borde superior (la luz rasante del sol o de la luna).
  void _drawMesas(
    Canvas canvas, {
    required double w,
    required double baseY,
    required double period,
    required double offset,
    required List<double> heights,
    required double maxHeight,
    required Paint paint,
    required Paint rim,
  }) {
    final count = heights.length;
    final first = (offset / period).floor() - 1;
    final slots = (w / period).ceil() + 3;
    for (var i = 0; i < slots; i++) {
      final k = first + i;
      final x = k * period - offset;
      final hgt = heights[((k % count) + count) % count] * maxHeight;
      final inset = period * 0.12;
      final topInset = period * 0.34;
      final path = Path()
        ..moveTo(x + inset, baseY)
        ..lineTo(x + topInset, baseY - hgt)
        ..lineTo(x + period - topInset, baseY - hgt)
        ..lineTo(x + period - inset, baseY)
        ..close();
      canvas.drawPath(path, paint);
      canvas.drawLine(
        Offset(x + topInset, baseY - hgt),
        Offset(x + period - topInset, baseY - hgt),
        rim,
      );
    }
  }

  // --- Props costados ---------------------------------------------------------

  void _drawProps(
    Canvas canvas,
    Perspective p,
    _Palette c, {
    required double sway,
  }) {
    if (!drawProps) return;
    // `_props` viene ordenado de lejos a cerca (mayor z primero).
    for (final prop in _props) {
      final alpha = _propAlpha(prop.z);
      if (alpha <= 0) continue;
      final body = prop.rect(p, sway: sway);
      if (body.width < 1 || body.height < 1) continue;
      if (body.right < 0 || body.left > p.width) continue; // fuera de pantalla
      _drawProp(canvas, prop, body, alpha, c);
    }
  }

  /// Los props lejanos se disuelven dentro de la bruma del horizonte.
  double _propAlpha(double z) =>
      ((_propFadeOutZ - z) / (_propFadeOutZ - _propFadeInZ)).clamp(0.0, 1.0);

  static Color _kindColor(int kind) => switch (kind) {
        0 => const Color(0xFF4E8C5A), // cactus
        1 => const Color(0xFFB98A5E), // roca
        2 => const Color(0xFF9C8348), // arbusto seco
        3 => const Color(0xFFB0714B), // meseta
        _ => const Color(0xFFE8E4D8), // cartel
      };

  void _drawProp(
    Canvas canvas,
    SideProp prop,
    Rect body,
    double alpha,
    _Palette c,
  ) {
    final kind = prop.style % _kindCount;

    // Tono propio de cada prop: dos vecinos no se funden en una hilera
    // indistinguible de siluetas del mismo color.
    final tone = ((prop.style * 37) % 21 - 10) / 100; // -0.10 .. +0.10
    var base = _kindColor(kind);
    // De noche todo cae hacia el tinte del desierto lunar; de día, color puro.
    if (c.night) base = Color.lerp(base, c.propNight, 0.45)!;
    final lift = tone >= 0 ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    base = Color.lerp(base, lift, tone.abs())!;

    // Sombra de contacto: el prop apoya en la orilla.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(body.center.dx, body.bottom),
        width: body.width * 0.86,
        height: max(3.0, body.width * 0.16),
      ),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.20 * alpha),
    );

    // Cuerpo con gradiente vertical (luz cenital sobre la silueta).
    final litTop = Color.lerp(base, const Color(0xFFFFFFFF), 0.16)!;
    final bodyPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, body.top),
        Offset(0, body.bottom),
        [
          litTop.withValues(alpha: alpha),
          base.withValues(alpha: alpha),
        ],
      );
    final accent = Paint()
      ..color = Color.lerp(base, const Color(0xFF000000), 0.4)!;

    switch (kind) {
      case 0:
        _drawCactus(canvas, body, bodyPaint);
      case 1:
        _drawRock(canvas, body, bodyPaint, accent, alpha);
      case 2:
        _drawBush(canvas, body, bodyPaint, accent, alpha);
      case 3:
        _drawMesa(canvas, body, bodyPaint, accent, alpha);
      default:
        _drawSign(canvas, body, bodyPaint, accent, alpha);
    }
  }

  /// Cactus saguaro: tronco redondeado con brazos que suben a los costados.
  /// Toda la figura vive dentro del rectángulo, ya garantizado fuera de la
  /// ruta.
  void _drawCactus(Canvas canvas, Rect body, Paint paint) {
    final cx = body.center.dx;
    final trunkW = max(3.0, body.width * 0.40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - trunkW * 0.5, body.top, trunkW, body.height),
        Radius.circular(trunkW * 0.5),
      ),
      paint,
    );

    if (body.height < 24) return;
    final armLen = min(body.width * 0.30, (body.width - trunkW) * 0.5);
    if (armLen < 2) return;
    final armThick = max(2.0, trunkW * 0.7);
    final armY = body.top + body.height * 0.5;
    final armH = body.height * 0.3;
    for (final dir in const [-1.0, 1.0]) {
      final inner = cx + dir * trunkW * 0.5;
      final outer = inner + dir * armLen;
      final x0 = min(inner, outer);
      final x1 = max(inner, outer);
      // Tramo horizontal: del tronco hacia afuera.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            x0,
            armY - armThick * 0.5,
            x1,
            armY + armThick * 0.5,
          ),
          Radius.circular(armThick * 0.5),
        ),
        paint,
      );
      // Tramo vertical apoyado contra la punta (así no se pasa del rect).
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            dir > 0 ? x1 - armThick : x0,
            armY - armH,
            armThick,
            armH,
          ),
          Radius.circular(armThick * 0.5),
        ),
        paint,
      );
    }
  }

  /// Roca: polígono irregular apoyado en el suelo con una costilla clara.
  void _drawRock(
    Canvas canvas,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
  ) {
    final l = body.left;
    final t = body.top + body.height * 0.3; // la roca usa la parte baja
    final wd = body.width;
    final ht = body.height * 0.7;
    final path = Path()
      ..moveTo(l, body.bottom)
      ..lineTo(l + wd * 0.08, t + ht * 0.45)
      ..lineTo(l + wd * 0.30, t + ht * 0.06)
      ..lineTo(l + wd * 0.60, t)
      ..lineTo(l + wd * 0.88, t + ht * 0.40)
      ..lineTo(l + wd, body.bottom)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(l + wd * 0.30, t + ht * 0.06),
      Offset(l + wd * 0.60, t),
      accent
        ..color = accent.color.withValues(alpha: 0.45 * alpha)
        ..strokeWidth = max(1.0, wd * 0.05)
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Arbusto seco: tres bolitas de follaje y unas varillas que asoman.
  void _drawBush(
    Canvas canvas,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
  ) {
    final cx = body.center.dx;
    final w = body.width;
    for (final (dx, rf) in const [
      (-0.20, 0.29),
      (0.21, 0.26),
      (0.01, 0.34),
    ]) {
      final r = w * rf;
      canvas.drawCircle(
        Offset(cx + dx * w, body.bottom - r * 0.85),
        r,
        paint,
      );
    }
    final twig = accent
      ..color = accent.color.withValues(alpha: alpha)
      ..strokeWidth = max(1.0, w * 0.035)
      ..strokeCap = StrokeCap.round;
    final hUp = min(body.height, w);
    for (final dx in const [-0.45, -0.15, 0.18, 0.48]) {
      canvas.drawLine(
        Offset(cx, body.bottom - hUp * 0.35),
        Offset(cx + dx * w, body.bottom - hUp * 0.35 - hUp * 0.5),
        twig,
      );
    }
  }

  /// Meseta: talud ancho, paredes cortadas y plancha plana con estratos.
  void _drawMesa(
    Canvas canvas,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
  ) {
    final w = body.width;
    final path = Path()
      ..moveTo(body.left, body.bottom)
      ..lineTo(body.left + w * 0.20, body.top + body.height * 0.28)
      ..lineTo(body.left + w * 0.28, body.top)
      ..lineTo(body.right - w * 0.22, body.top)
      ..lineTo(body.right - w * 0.14, body.top + body.height * 0.34)
      ..lineTo(body.right, body.bottom)
      ..close();
    canvas.drawPath(path, paint);

    // Estratos: tres líneas recortadas a la silueta.
    canvas.save();
    canvas.clipPath(path);
    final strata = accent
      ..color = accent.color.withValues(alpha: 0.35 * alpha)
      ..strokeWidth = max(1.0, w * 0.045);
    for (final f in const [0.45, 0.62, 0.80]) {
      canvas.drawLine(
        Offset(body.left, body.top + body.height * f),
        Offset(body.right, body.top + body.height * f),
        strata,
      );
    }
    canvas.restore();
  }

  /// Cartel de ruta: poste, panel redondeado y dos barras que simulan texto.
  void _drawSign(
    Canvas canvas,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
  ) {
    final w = body.width;
    final cx = body.center.dx;
    final panelH = body.height * 0.38;
    final postW = max(2.0, w * 0.12);

    final postTop = body.top + panelH;
    canvas.drawRect(
      Rect.fromLTWH(cx - postW * 0.5, postTop, postW, body.bottom - postTop),
      accent..color = accent.color.withValues(alpha: alpha),
    );

    final radius = Radius.circular(max(2.0, w * 0.10));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.left, body.top, w, panelH),
        radius,
      ),
      paint,
    );
    final bar = accent..color = accent.color.withValues(alpha: alpha * 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.left + w * 0.16,
          body.top + panelH * 0.28,
          w * 0.68,
          panelH * 0.16,
        ),
        Radius.circular(panelH * 0.08),
      ),
      bar,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.left + w * 0.24,
          body.top + panelH * 0.58,
          w * 0.52,
          panelH * 0.14,
        ),
        Radius.circular(panelH * 0.07),
      ),
      bar,
    );
  }

  // --- Marcas viales ----------------------------------------------------------

  /// Manchones de la divisoria `lane` (±0.5): la fase avanza con el juego en
  /// coordenada de mundo y cada manchón se afila con la perspectiva.
  void _drawLaneDashes(Canvas canvas, Perspective p, double lane, _Palette c) {
    for (var m = -1;; m++) {
      final zNear = _dashZMin + _dashPhase + m * _dashPeriod;
      if (zNear > _dashZMax) break;
      final zFar = zNear + _dashLen;
      if (zFar <= _dashZMin) continue; // todavía no entró en pantalla
      _drawLaneSegment(
        canvas,
        p,
        lane,
        zNear: max(zNear, _dashZMin), // cortado en el borde inferior
        zFar: min(zFar, _dashZMax),
        widthBase: 6,
        color: c.roadLine,
        alpha: 0.95,
      );
    }
  }

  /// Segmento de línea de ruta entre dos profundidades, afilado por la
  /// perspectiva como cualquier objeto del mundo. [lane] puede superar 1:
  /// así se dibujan las líneas de borde, que caen fuera de la ruta de juego
  /// (el asfalto es más ancho, ver [roadExtraFrac]).
  void _drawLaneSegment(
    Canvas canvas,
    Perspective p,
    double lane, {
    required double zNear,
    required double zFar,
    required double widthBase,
    required Color color,
    double alpha = 1,
  }) {
    if (zFar <= zNear) return;
    final tN = (1.0 / zNear).clamp(0.0, 1.0);
    final tF = (1.0 / zFar).clamp(0.0, 1.0);
    final half = p.baseWidth * 0.5;
    final xN = p.vanishX + lane * half * tN;
    final xF = p.vanishX + lane * half * tF;
    final wN = widthBase * tN * 0.5;
    final wF = widthBase * tF * 0.5;
    final path = Path()
      ..moveTo(xN - wN, p.yAtT(tN))
      ..lineTo(xN + wN, p.yAtT(tN))
      ..lineTo(xF + wF, p.yAtT(tF))
      ..lineTo(xF - wF, p.yAtT(tF))
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: alpha));
  }
}

/// Prop de la orilla: vive fuera de la carretera a su profundidad `z` y se
/// proyecta con la misma ley que las rayas del asfalto (`t = 1/z`), así que
/// nace chico junto al horizonte, crece a medida que se acerca y termina
/// saliendo de pantalla por las esquinas inferiores.
///
/// El borde más cercano a la ruta siempre respeta un hueco mínimo
/// ([minGapFrac] del ancho del corredor), por lo que jamás tapa el asfalto
/// ni a los obstáculos.
class SideProp {
  SideProp({
    required this.side,
    required this.z,
    required this.widthFrac,
    required this.heightFrac,
    required this.lateralFrac,
    required this.style,
  });

  /// Hueco mínimo entre el asfalto y el prop, en fracciones del ancho del
  /// corredor (sobre la línea base; en pantalla se escala con `t`).
  ///
  /// Va más allá de [MapRenderer.roadExtraFrac] (0.07): con 0.10 el prop
  /// jamás pisa la carretera aunque la guiñada lo empuje hacia adentro.
  static const double minGapFrac = 0.10;

  /// -1 = lado izquierdo, +1 = lado derecho.
  final int side;

  /// Profundidad en coordenada de mundo: 1 = línea base, mayor = más lejos.
  double z;

  /// Ancho del prop sobre el ancho del corredor (en la línea base).
  final double widthFrac;

  /// Alto del prop sobre la altura de la pantalla (en la línea base).
  final double heightFrac;

  /// Separación extra desde el hueco mínimo (0 = lo más cerca de la ruta).
  final double lateralFrac;

  /// Semilla del aspecto: `style % MapRenderer._kindCount` elige el tipo de
  /// prop y el resto varía tono y detalles.
  final int style;

  /// Profundidad normalada proyectada en pantalla (misma ley que las rayas).
  double get t => (1.0 / z).clamp(0.0, 1.0);

  /// X del borde del prop más cercano a la ruta.
  ///
  /// [sway] aplica la guiñada de cámara del parallax, pero siempre con tope:
  /// el borde nunca puede cruzar hacia el asfalto.
  double innerEdgeX(Perspective p, {double sway = 0}) {
    final t = this.t;
    final edge = p.xAtT(side.toDouble(), t);
    final minGap = p.baseWidth * minGapFrac * t;
    final gap = p.baseWidth * (minGapFrac + 0.14 * lateralFrac) * t;
    final raw = edge + side * gap + sway * 0.06 * t;
    return side < 0 ? min(raw, edge - minGap) : max(raw, edge + minGap);
  }

  /// Rectángulo del cuerpo en pantalla (borde inferior apoyado en el suelo a
  /// la profundidad `z`).
  Rect rect(Perspective p, {double sway = 0}) {
    final t = this.t;
    final inner = innerEdgeX(p, sway: sway);
    final width = p.baseWidth * widthFrac * t;
    final height = p.height * heightFrac * t;
    final baseY = p.yAtT(t);
    return side < 0
        ? Rect.fromLTRB(inner - width, baseY - height, inner, baseY)
        : Rect.fromLTRB(inner, baseY - height, inner + width, baseY);
  }
}

// --- Paletas -----------------------------------------------------------------

class _Palette {
  const _Palette({
    required this.skyTop,
    required this.skyBottom,
    required this.star,
    required this.body,
    required this.bodyGlow,
    required this.bodyShade,
    required this.cloud,
    required this.ridgeFar,
    required this.ridgeLit,
    required this.duneNear,
    required this.sandFar,
    required this.sandNear,
    required this.shoulder,
    required this.roadFar,
    required this.roadNear,
    required this.roadLine,
    required this.stripe,
    required this.haze,
    required this.propNight,
    required this.night,
  });

  final Color skyTop;
  final Color skyBottom;

  /// Estrellas (solo se dibujan de noche).
  final Color star;

  /// Sol (día) o luna (noche), su halo y los cráteres de la luna.
  final Color body;
  final Color bodyGlow;
  final Color bodyShade;

  final Color cloud;
  final Color ridgeFar;
  final Color ridgeLit;
  final Color duneNear;
  final Color sandFar;
  final Color sandNear;
  final Color shoulder;
  final Color roadFar;
  final Color roadNear;

  /// Pintura de las marcas viales (divisores y bordes).
  final Color roadLine;

  final Color stripe;
  final Color haze;

  /// Tinte al que caen los props de la orilla cuando es de noche.
  final Color propNight;

  /// true en el tema oscuro (noche estrellada con luna).
  final bool night;
}

const _Palette _dark = _Palette(
  skyTop: Color(0xFF060A1C),
  skyBottom: Color(0xFF3A2E4E),
  star: Color(0xFFFFFFFF),
  body: Color(0xFFEDF1FB),
  bodyGlow: Color(0xFFBFC9EE),
  bodyShade: Color(0xFFC7CFE6),
  cloud: Color(0x1CFFFFFF),
  ridgeFar: Color(0xFF241E3C),
  ridgeLit: Color(0xFF5A4C7A),
  duneNear: Color(0xFF4A4066),
  sandFar: Color(0xFF403856),
  sandNear: Color(0xFF2C2644),
  shoulder: Color(0xFF221D36),
  roadFar: Color(0xFF262B40),
  roadNear: Color(0xFF0E1119),
  roadLine: Color(0xFFDCE2F5),
  stripe: Color(0xFF4A5686),
  haze: Color(0xFF2E3358),
  propNight: Color(0xFF0C1024),
  night: true,
);

const _Palette _light = _Palette(
  skyTop: Color(0xFF4FA6E6),
  skyBottom: Color(0xFFFFE0A8),
  star: Color(0xFFFFFFFF),
  body: Color(0xFFFFF6D2),
  bodyGlow: Color(0xFFFFDC9A),
  bodyShade: Color(0xFFFFE9B8),
  cloud: Color(0xE6FFFFFF),
  ridgeFar: Color(0xFFDCC3A0),
  ridgeLit: Color(0xFFFFF0D2),
  duneNear: Color(0xFFEFCB8E),
  sandFar: Color(0xFFF4E0B6),
  sandNear: Color(0xFFE2BC7E),
  shoulder: Color(0xFFC9A268),
  roadFar: Color(0xFFA7ADB5),
  roadNear: Color(0xFF5C6169),
  roadLine: Color(0xFFFFFDF2),
  stripe: Color(0xFFFFFFFF),
  haze: Color(0xFFF8E9CC),
  propNight: Color(0xFF1A2233),
  night: false,
);
