import 'dart:math';

import 'package:flutter/material.dart';

import 'power_up_component.dart';

/// Feedback instantáneo de la partida (Fase 3): chispas, anillos expansivos,
/// etiquetas flotantes, destello de pantalla y sacudida de cámara.
///
/// No es un componente de Flame: lo actualiza y dibuja `RunnerGame` (igual que
/// hace con `MapRenderer`), así todo el juice vive en el canvas del juego y
/// sigue sin tocar los widgets de Flutter (GameHeader y GameControls
/// intactos).
///
/// Nada se dibuja con TextPainter: en los previews (que corren con la fuente
/// de relleno del entorno de test) el texto sale como cajas sólidas — el mismo
/// motivo por el que el "x2" de los power-ups es un trazo. El "+1" también es
/// un trazo, así se lee igual en previews, tests y dispositivo.
class Juice {
  Juice({Random? random}) : _rng = random ?? Random();

  final Random _rng;

  // --- Tuneo ---------------------------------------------------------------
  /// Amplitud máxima de la sacudida (px): se nota sin marear y sin despegar
  /// el HUD (que además queda fuera del temblor).
  static const double maxShake = 12;

  /// Techo de cada lista: un bucle largo no puede acumular partículas para
  /// siempre (se descarta la más vieja).
  static const int maxRings = 32;
  static const int maxSparks = 170;
  static const int maxLabels = 10;

  /// Decaimiento exponencial de la sacudida: con estos valores un golpe fuerte
  /// (11 px) queda en cero pasados ~0.6 s, que es la ventana de gracia de la
  /// muerte (ver `RunnerGame._deathGrace`).
  static const double _shakeDecay = 9;

  /// Vaivén del temblor (rad/s): ~9 Hz, rápido pero legible.
  static const double _shakeWobble = 58;

  /// Distancia que sube una etiqueta flotante antes de desaparecer (px).
  static const double _labelRise = 46;

  static const Color coinColor = Color(0xFF46DDF2);
  static const Color hitColor = Color(0xFFE0483C);
  static const Color shieldColor = Color(0xFF378ADD);

  // --- Estado --------------------------------------------------------------
  final List<JuiceRing> _rings = [];
  final List<JuiceSpark> _sparks = [];
  final List<JuiceLabel> _labels = [];

  double _shake = 0;
  double _phase = 0;

  Color? _flashColor;
  double _flashAlpha = 0;
  double _flashRate = 0;

  /// Anillos, chispas y etiquetas vivos: vistas de solo lectura pensadas para
  /// tests y debug (el render itera las listas internas directamente).
  List<JuiceRing> get rings => List<JuiceRing>.unmodifiable(_rings);
  List<JuiceSpark> get sparks => List<JuiceSpark>.unmodifiable(_sparks);
  List<JuiceLabel> get labels => List<JuiceLabel>.unmodifiable(_labels);

  /// Amplitud actual de la sacudida en px (0 = cámara quieta).
  double get shake => _shake;

  /// Destello de pantalla vigente: color y opacidad (0 = sin destello).
  Color? get flashColor => _flashAlpha > 0 ? _flashColor : null;
  double get flashAlpha => _flashAlpha;

  /// Desplazamiento de cámara del frame actual. Solo cambia al llamar a
  /// [update], así que varias llamadas a [render] en el mismo frame miden lo
  /// mismo.
  Offset get shakeOffset {
    if (_shake <= 0) return Offset.zero;
    return Offset(sin(_phase) * _shake, cos(_phase * 1.37) * _shake * 0.6);
  }

  /// true cuando no queda nada por dibujar. Lo usan los tests para verificar,
  /// por ejemplo, que el juice de la muerte terminó de disiparse.
  bool get isIdle =>
      _rings.isEmpty &&
      _sparks.isEmpty &&
      _labels.isEmpty &&
      _shake == 0 &&
      _flashAlpha == 0;

  // --- Eventos -------------------------------------------------------------

  /// Recogida de moneda: anillo cian, chispas y el "+1" flotando.
  void coinPickup(Offset at) {
    _addRing(at, r0: 5, r1: 34, color: coinColor, duration: 0.34);
    _addBurst(
      at,
      count: 7,
      color: coinColor,
      speed: 170,
      life: 0.5,
      size: 3,
      upBias: 0.35,
    );
    _addLabel(at, color: coinColor);
  }

  /// Recogida de power-up: todo más grande, en el color del poder, con la
  /// ficha del poder flotando y un destello suave del mismo tinte.
  void powerUpPickup(Offset at, PowerUpKind kind) {
    _addRing(at, r0: 8, r1: 58, color: kind.color, duration: 0.45);
    _addBurst(
      at,
      count: 14,
      color: kind.color,
      speed: 240,
      life: 0.55,
      size: 3.4,
      upBias: 0.3,
    );
    _addLabel(at, color: kind.color, icon: kind);
    flash(kind.color, 0.25, duration: 0.3);
  }

  /// El escudo absorbió el golpe: onda expansiva azul y nada rojo (el jugador
  /// salió ileso y conviene que se note que lo salvó el escudo).
  void shieldAbsorb(Offset at) {
    _addRing(at, r0: 12, r1: 78, color: shieldColor, duration: 0.5);
    _addBurst(
      at,
      count: 16,
      color: shieldColor,
      speed: 280,
      life: 0.55,
      size: 3.2,
      upBias: 0.25,
    );
    flash(shieldColor, 0.4, duration: 0.32);
    addShake(3.5);
  }

  /// Golpe pagado con diamantes: el jugador queda en pie, pero el golpe se
  /// tiene que ver (destello rojo + sacudida corta).
  void hitPaid(Offset at) {
    _addRing(at, r0: 6, r1: 46, color: hitColor, duration: 0.36);
    _addBurst(
      at,
      count: 14,
      color: hitColor,
      speed: 250,
      life: 0.5,
      size: 3.4,
      gravity: 720,
    );
    flash(hitColor, 0.55, duration: 0.3);
    addShake(6);
  }

  /// Fin de partida: el golpe más fuerte de todos. Su ventana de disipación
  /// es la que `RunnerGame` espera antes de pausar el motor.
  void death(Offset at) {
    _addRing(at, r0: 8, r1: 96, color: hitColor, duration: 0.65);
    _addBurst(
      at,
      count: 24,
      color: hitColor,
      speed: 330,
      life: 0.8,
      size: 3.8,
      gravity: 720,
    );
    flash(hitColor, 0.9, duration: 0.55);
    addShake(11);
  }

  /// Polvo al aterrizar: anillo aplastado apoyado en el piso + nube baja.
  /// [dark] elige el tinte según el tema, para que el polvo se note igual en
  /// la calle clara y en la oscura.
  void landDust(Offset at, {required bool dark}) {
    final dust = dark ? const Color(0xFFE9E4D8) : const Color(0xFF77725F);
    _addRing(
      at,
      r0: 4,
      r1: 46,
      color: dust,
      duration: 0.42,
      flatten: 0.3,
    );
    _addBurst(
      at,
      count: 8,
      color: dust,
      speed: 130,
      life: 0.45,
      size: 3.2,
      gravity: 260,
      upBias: 0.45,
    );
  }

  /// Destello de pantalla en viñeta: transparente en el centro y del color en
  /// los bordes. Un destello más fuerte nunca lo pisa uno más débil.
  void flash(Color color, double strength, {double duration = 0.3}) {
    if (strength < _flashAlpha) return;
    _flashColor = color;
    _flashAlpha = strength.clamp(0.0, 1.0);
    _flashRate = strength / duration;
  }

  /// Suma amplitud a la sacudida de cámara, acotada a [maxShake].
  void addShake(double amount) {
    _shake = min(maxShake, _shake + amount);
  }

  // --- Ciclo ----------------------------------------------------------------

  /// Avanza todos los efectos; lo llama `RunnerGame` una vez por frame.
  void update(double dt) {
    _phase += dt * _shakeWobble;

    if (_shake > 0) {
      _shake *= exp(-dt * _shakeDecay);
      if (_shake < 0.06) _shake = 0;
    }

    if (_flashAlpha > 0) {
      _flashAlpha -= _flashRate * dt;
      if (_flashAlpha <= 0) {
        _flashAlpha = 0;
        _flashColor = null;
        _flashRate = 0;
      }
    }

    for (var i = _rings.length - 1; i >= 0; i--) {
      final ring = _rings[i];
      ring.life -= dt;
      if (ring.life <= 0) _rings.removeAt(i);
    }

    for (var i = _sparks.length - 1; i >= 0; i--) {
      final spark = _sparks[i];
      spark.life -= dt;
      if (spark.life <= 0) {
        _sparks.removeAt(i);
        continue;
      }
      spark.vel = Offset(spark.vel.dx, spark.vel.dy + spark.gravity * dt);
      spark.pos += spark.vel * dt;
    }

    for (var i = _labels.length - 1; i >= 0; i--) {
      final label = _labels[i];
      label.life -= dt;
      if (label.life <= 0) _labels.removeAt(i);
    }
  }

  // --- Dibujo ---------------------------------------------------------------

  /// Partículas, anillos y etiquetas. Va DENTRO de la traslación de la
  /// sacudida (se encarga `RunnerGame`): el feedback es parte del mundo y
  /// tiembla con él.
  void render(Canvas canvas) {
    for (final ring in _rings) {
      final a = ring.alpha;
      if (a <= 0) continue;
      canvas.drawOval(
        Rect.fromCenter(
          center: ring.at,
          width: ring.radius * 2,
          height: ring.radius * 2 * ring.flatten,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (5 - 3.5 * ring.progress).clamp(1.5, 5.0)
          ..color = ring.color.withValues(alpha: a * 0.95),
      );
    }

    for (final spark in _sparks) {
      canvas.drawCircle(
        spark.pos,
        spark.size * (0.55 + 0.45 * spark.alpha),
        Paint()..color = spark.color.withValues(alpha: spark.alpha),
      );
    }

    for (final label in _labels) {
      _renderLabel(canvas, label);
    }
  }

  /// Viñeta de destello, fuera de la sacudida y por encima del mundo (pero
  /// debajo del HUD): el centro queda despejado para que siga leyéndose la
  /// pista y el corredor.
  void renderFlash(Canvas canvas, Rect area) {
    if (_flashAlpha <= 0 || area.isEmpty) return;
    final color = _flashColor ?? hitColor;
    canvas.drawRect(
      area,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.75,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: _flashAlpha),
          ],
        ).createShader(area),
    );
  }

  void _renderLabel(Canvas canvas, JuiceLabel label) {
    final t = label.progress;
    final a = t < 0.55 ? 1.0 : 1 - (t - 0.55) / 0.45;
    if (a <= 0) return;

    // Sube y se achica al ir saliendo: aparece grande y se va empequeñeciendo.
    final center = Offset(label.at.dx, label.at.dy - label.rise);
    final scale = 1.35 - 0.35 * t;

    final icon = label.icon;
    if (icon != null) {
      // La ficha del power-up tal cual se ve en el corredor y en el HUD.
      final side = 30 * scale;
      PowerUpComponent.drawBadge(
        canvas,
        icon,
        Rect.fromCenter(center: center, width: side, height: side),
        a,
      );
      return;
    }
    _drawPlusOne(canvas, center, label.color, a, scale);
  }

  /// El "+1" de las monedas, trazado a mano (ver doc de la clase). Se pinta
  /// dos veces: primero un contorno oscuro y encima el color, para que se lea
  /// sobre la calle clara y sobre la oscura.
  static void _drawPlusOne(
    Canvas canvas,
    Offset c,
    Color color,
    double a,
    double scale,
  ) {
    final s = scale;
    final cxPlus = c.dx - 7 * s;
    final cxOne = c.dx + 7 * s;

    final glyphs = Path()
      // "+"
      ..moveTo(cxPlus - 5 * s, c.dy)
      ..lineTo(cxPlus + 5 * s, c.dy)
      ..moveTo(cxPlus, c.dy - 5 * s)
      ..lineTo(cxPlus, c.dy + 5 * s)
      // "1": banderita, asta y base.
      ..moveTo(cxOne - 4 * s, c.dy - 3.5 * s)
      ..lineTo(cxOne, c.dy - 6 * s)
      ..lineTo(cxOne, c.dy + 6 * s)
      ..moveTo(cxOne - 4 * s, c.dy + 6 * s)
      ..lineTo(cxOne + 4 * s, c.dy + 6 * s);

    canvas.drawPath(
      glyphs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 5.5 * s
        ..color = const Color(0xFF10182B).withValues(alpha: 0.55 * a),
    );
    canvas.drawPath(
      glyphs,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.6 * s
        ..color = color.withValues(alpha: a),
    );
  }

  // --- Utilidades -----------------------------------------------------------

  void _addRing(
    Offset at, {
    required double r0,
    required double r1,
    required Color color,
    double duration = 0.4,
    double flatten = 1,
  }) {
    if (_rings.length >= maxRings) _rings.removeAt(0);
    _rings.add(
      JuiceRing(
        at: at,
        r0: r0,
        r1: r1,
        color: color,
        duration: duration,
        flatten: flatten,
      ),
    );
  }

  void _addBurst(
    Offset at, {
    required int count,
    required Color color,
    required double speed,
    double life = 0.5,
    double size = 3,
    double gravity = 520,
    double upBias = 0,
  }) {
    for (var i = 0; i < count; i++) {
      if (_sparks.length >= maxSparks) _sparks.removeAt(0);
      final angle = _rng.nextDouble() * 2 * pi;
      final v = speed * (0.45 + 0.55 * _rng.nextDouble());
      _sparks.add(
        JuiceSpark(
          pos: at,
          // upBias empuja hacia arriba (el eje Y de pantalla crece hacia abajo).
          vel: Offset(cos(angle) * v, sin(angle) * v - upBias * v),
          color: color,
          size: size * (0.7 + 0.6 * _rng.nextDouble()),
          life: life * (0.7 + 0.6 * _rng.nextDouble()),
          gravity: gravity,
        ),
      );
    }
  }

  void _addLabel(Offset at, {required Color color, PowerUpKind? icon}) {
    if (_labels.length >= maxLabels) _labels.removeAt(0);
    _labels.add(
      JuiceLabel(at: at, color: color, icon: icon, duration: 0.75),
    );
  }

  /// Limpia todo (reinicio de partida).
  void reset() {
    _rings.clear();
    _sparks.clear();
    _labels.clear();
    _shake = 0;
    _phase = 0;
    _flashColor = null;
    _flashAlpha = 0;
    _flashRate = 0;
  }
}

/// Anillo expansivo: [r0] -> [r1] con la expansión frenando hacia el final.
///
/// [flatten] = 1 es un círculo (recogidas) y < 1 un óvalo aplastado apoyado
/// en el piso (polvo del aterrizaje).
class JuiceRing {
  JuiceRing({
    required this.at,
    required this.r0,
    required this.r1,
    required this.color,
    required double duration,
    required this.flatten,
  })  : duration = duration,
        life = duration;

  /// Centro en coordenadas de pantalla.
  final Offset at;

  final double r0;
  final double r1;
  final Color color;

  /// Vida total, en segundos.
  final double duration;

  /// 1 = círculo; < 1 = óvalo (vértice vertical aplastado).
  final double flatten;

  double life;

  /// 0 al nacer -> 1 al morir.
  double get progress => (1 - life / duration).clamp(0.0, 1.0);

  /// Radio actual: la expansión se frena sola hacia el final.
  double get radius => r0 + (r1 - r0) * _easeOut(progress);

  /// Opacidad: arranca plena y se apaga junto con el anillo.
  double get alpha => 1 - progress;
}

/// Chispita con velocidad propia y gravedad.
class JuiceSpark {
  JuiceSpark({
    required this.pos,
    required this.vel,
    required this.color,
    required this.size,
    required double life,
    required this.gravity,
  })  : life = life,
        maxLife = life;

  Offset pos;
  Offset vel;
  final Color color;
  final double size;

  /// px/s² hacia abajo.
  final double gravity;

  final double maxLife;
  double life;

  /// 1 al nacer -> 0 al morir.
  double get alpha => (life / maxLife).clamp(0.0, 1.0);
}

/// Etiqueta que sube y se apaga: el "+1" de las monedas o la ficha del
/// power-up recogido.
class JuiceLabel {
  JuiceLabel({
    required this.at,
    required this.color,
    required this.icon,
    required double duration,
  })  : duration = duration,
        life = duration;

  /// Punto de partida, en coordenadas de pantalla.
  final Offset at;

  final Color color;

  /// `null` = etiqueta "+1" (monedas); con valor flota la ficha del poder.
  final PowerUpKind? icon;

  final double duration;
  double life;

  /// 0 al nacer -> 1 al morir.
  double get progress => (1 - life / duration).clamp(0.0, 1.0);

  /// Cuánto ya subió, en px.
  double get rise => _easeOut(progress) * Juice._labelRise;
}

double _easeOut(double t) => 1 - (1 - t) * (1 - t);
