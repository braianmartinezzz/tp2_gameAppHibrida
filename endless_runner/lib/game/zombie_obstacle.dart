import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'depth_component.dart';
import 'zombie_sprites.dart';

/// Cómo se mueve un zombi de costado mientras avanza hacia el jugador.
enum ZombieBehavior {
  /// Camina de ida y vuelta entre dos carriles (patrulla).
  patrol,

  /// Persigue el carril del jugador hasta cierta profundidad; después se
  /// "compromete" y corre en línea recta (así siempre se puede esquivar).
  chase,
}

/// Los tres tipos de zombi. Cada uno se distingue a simple vista (color,
/// tamaño, aro del piso) y en cómo se mueve.
enum ZombieKind {
  /// Tanque: grande, verde pálido, patrulla despacio entre dos carriles.
  slow(
    behavior: ZombieBehavior.patrol,
    width: 56,
    height: 104,
    lateralSpeed: 0.40,
    patrolSpan: 1.0,
    stepRate: 5,
    torso: 0.86,
    skin: Color(0xFF9DB872),
    clothes: Color(0xFF7A6A44),
    ring: Color(0xFFB7D957),
    eyes: Color(0xFFEDE9A6),
  ),

  /// Caminante común: tamaño medio, patrulla todo el ancho del corredor.
  normal(
    behavior: ZombieBehavior.patrol,
    width: 44,
    height: 92,
    lateralSpeed: 0.70,
    patrolSpan: 2.0,
    stepRate: 8,
    torso: 0.70,
    skin: Color(0xFF5FA36A),
    clothes: Color(0xFF3E5C8A),
    ring: Color(0xFFF2A33D),
    eyes: Color(0xFFFFF3B0),
  ),

  /// Corredor: chico, violáceo y de ojos rojos; persigue al jugador.
  fast(
    behavior: ZombieBehavior.chase,
    width: 36,
    height: 82,
    lateralSpeed: 1.30,
    patrolSpan: 0,
    stepRate: 13,
    torso: 0.58,
    skin: Color(0xFF9A6FB8),
    clothes: Color(0xFF8E2B2A),
    ring: Color(0xFFE24B4A),
    eyes: Color(0xFFFF4D4D),
  );

  const ZombieKind({
    required this.behavior,
    required this.width,
    required this.height,
    required this.lateralSpeed,
    required this.patrolSpan,
    required this.stepRate,
    required this.torso,
    required this.skin,
    required this.clothes,
    required this.ring,
    required this.eyes,
  });

  final ZombieBehavior behavior;

  /// Ancho y alto en la línea base (t = 1), sin el factor de dificultad.
  final double width;
  final double height;

  /// Velocidad lateral base en carriles por segundo.
  final double lateralSpeed;

  /// Ancho (en carriles) del tramo que patrulla. Ignorado al perseguir.
  final double patrolSpan;

  /// Velocidad del ciclo de caminata (rad/s) para la animación.
  final double stepRate;

  /// Ancho del torso como fracción del ancho total.
  final double torso;

  final Color skin;
  final Color clothes;

  /// Color del aro en el piso: se lee desde lejos y distingue el tipo.
  final Color ring;
  final Color eyes;

  /// Dificultad (0..1) a partir de la cual puede aparecer el zombi rápido.
  static const double fastUnlock = 0.08;

  /// Elige el tipo según la [difficulty] (0..1) y un número [roll] (0..1).
  ///
  /// Al principio casi todo son lentos; con el tiempo se pierden lentos y
  /// ganan peso los rápidos (que no aparecen antes de [fastUnlock]).
  static ZombieKind roll(double difficulty, double roll) {
    final d = difficulty.clamp(0.0, 1.0).toDouble();
    final pFast = d < fastUnlock ? 0.0 : 0.10 + 0.40 * d;
    final pSlow = 0.55 - 0.35 * d;
    if (roll < pFast) return ZombieKind.fast;
    if (roll < pFast + pSlow) return ZombieKind.slow;
    return ZombieKind.normal;
  }
}

/// Zombi móvil que funciona como obstáculo.
///
/// Hereda de [DepthComponent] (que a su vez es un `PositionComponent`), así
/// reutiliza la ley de movimiento en perspectiva y la colisión por fila +
/// carril + altura de los demás obstáculos. Lo propio del zombi es el
/// movimiento lateral —patrulla o persecución—, los diferenciadores visuales
/// por tipo y cómo escala con la dificultad.
///
/// Todos los tipos bajan a la velocidad del piso: así la separación en el
/// tiempo con los obstáculos fijos que decide el spawner se mantiene hasta
/// el jugador. Lo que cambia entre tipos es el movimiento de costado.
///
/// Altura: a la altura del jugador (profundidad ~0,86) hasta el más bajo mide
/// ~70 px, más que el techo del salto (~60 px): ninguno se salta ni se pasa
/// agachado, hay que cambiar de carril.
class ZombieObstacle extends DepthComponent {
  ZombieObstacle({
    required super.lane,
    required super.speed,
    required super.perspective,
    this.kind = ZombieKind.normal,
    this.difficulty = 0,
    double? phase,
    Random? random,
  }) : super(
          position: Vector2.zero(),
          size: Vector2.all(1),
          anchor: Anchor.topLeft,
        ) {
    final rng = random ?? Random();
    _phase = rng.nextDouble() * 2 * pi;
    _dir = rng.nextBool() ? 1 : -1;

    if (kind.behavior == ZombieBehavior.patrol) {
      // `lane` es el centro de la patrulla; el tramo no sale del corredor.
      final half = kind.patrolSpan * 0.5;
      patrolMin = (lane - half).clamp(-1.0, 1.0).toDouble();
      patrolMax = (lane + half).clamp(-1.0, 1.0).toDouble();
      // Arranca en un punto cualquiera del tramo (o en el que se pida).
      final p = (phase ?? rng.nextDouble()).clamp(0.0, 1.0).toDouble();
      this.lane = patrolMin + (patrolMax - patrolMin) * p;
    } else {
      patrolMin = -1;
      patrolMax = 1;
    }
    syncGeometry();
  }

  /// Tipo de zombi (define aspecto, tamaño y movimiento).
  final ZombieKind kind;

  /// Dificultad de la partida al nacer (0..1): agranda y acelera al zombi.
  final double difficulty;

  /// Límites de la patrulla en carriles (solo para [ZombieBehavior.patrol]).
  late final double patrolMin;
  late final double patrolMax;

  /// Carril que persigue el zombi rápido: el juego lo refresca cada frame
  /// con la posición del jugador.
  double targetLane = 0;

  /// true si en el frame anterior estaba tocando al jugador.
  bool wasTouching = false;

  /// Profundidad (t) a partir de la cual el zombi que persigue deja de
  /// seguir al jugador y corre derecho: da tiempo de sobra para esquivar.
  static const double lockT = 0.55;

  /// Cuánto sube la velocidad lateral con la dificultad máxima (+60 %).
  static const double speedGain = 0.6;

  /// Cuánto crece el zombi con la dificultad máxima (+12 %).
  static const double sizeGain = 0.12;

  double _phase = 0;
  double _time = 0;
  double _dir = 1;
  bool _locked = false;

  /// true cuando el zombi que persigue ya fijó su carril.
  bool get locked => _locked;

  /// Dirección actual de la patrulla (+1 derecha, -1 izquierda).
  double get direction => _dir;

  /// Velocidad lateral efectiva (carriles/seg): sube con la dificultad.
  double get lateralSpeed =>
      kind.lateralSpeed * (1 + speedGain * difficulty.clamp(0.0, 1.0));

  /// Factor de tamaño por dificultad.
  double get sizeFactor => 1 + sizeGain * difficulty.clamp(0.0, 1.0);

  // --- Ciclo -----------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    advance(dt); // misma ley de perspectiva que el resto de los actores
    switch (kind.behavior) {
      case ZombieBehavior.patrol:
        _patrol(dt);
      case ZombieBehavior.chase:
        _chase(dt);
    }
    syncGeometry();
  }

  /// Ida y vuelta entre [patrolMin] y [patrolMax].
  void _patrol(double dt) {
    lane += _dir * lateralSpeed * dt;
    if (lane >= patrolMax) {
      lane = patrolMax;
      _dir = -1;
    } else if (lane <= patrolMin) {
      lane = patrolMin;
      _dir = 1;
    }
  }

  /// Se acerca al [targetLane] hasta [lockT]; después mantiene el carril.
  void _chase(double dt) {
    if (!_locked && t >= lockT) _locked = true;
    if (_locked) return;
    final diff = targetLane - lane;
    final step = lateralSpeed * dt;
    lane = diff.abs() <= step ? targetLane : lane + step * diff.sign;
  }

  /// Recalcula posición y tamaño a partir de [baseY] y [lane].
  void syncGeometry() {
    final s = depthScale;
    final w = kind.width * sizeFactor * s;
    final h = kind.height * sizeFactor * s;
    position.setValues(centerX - w * 0.5, baseY - h);
    size.setValues(w, h);
  }

  // --- Dibujo ----------------------------------------------------------------
  //
  // Pixel-art de 8 bits, en la línea del corredor (ver zombie_sprites.dart):
  //  - slow: tanque panzón y calvo, con suturas y la panza al aire.
  //  - normal: oficinista con corbata floja y costillas a la vista.
  //  - fast: flaco, de capucha roja, ojos rojos y mandíbula desencajada.
  // Cada uno tiene dos cuadros que se alternan al caminar.

  /// Paleta de cada tipo, armada una sola vez.
  static final Map<ZombieKind, Map<String, Color>> _palettes = {
    for (final k in ZombieKind.values)
      k: ZombiePalette.build(
        skin: k.skin,
        clothes: k.clothes,
        eyes: k.eyes,
      ),
  };

  PixelSprite _sprite(int frame) => switch (kind) {
        ZombieKind.slow => frame == 0 ? ZombieSprites.slow0 : ZombieSprites.slow1,
        ZombieKind.normal =>
          frame == 0 ? ZombieSprites.normal0 : ZombieSprites.normal1,
        ZombieKind.fast => frame == 0 ? ZombieSprites.fast0 : ZombieSprites.fast1,
      };

  @override
  void render(Canvas canvas) {
    final a = alpha;
    if (a <= 0) return;
    final w = size.x;
    final h = size.y;
    if (w <= 0 || h <= 0) return;

    final sway = sin(_time * kind.stepRate + _phase); // -1..1
    final bob = sway.abs() * h * 0.02;

    // Sombra y aro del color del tipo en el piso.
    final groundH = (h * 0.06 + 3).clamp(3.0, 12.0).toDouble();
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h),
        width: w * 1.05,
        height: groundH,
      ),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.32 * a),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h),
        width: w * 1.2,
        height: groundH * 1.3,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.5, w * 0.04)
        ..color = kind.ring.withValues(alpha: 0.85 * a),
    );

    // Estela de velocidad sobre la cabeza del que corre.
    if (kind.behavior == ZombieBehavior.chase) {
      final streak = Paint()
        ..strokeWidth = max(1.0, w * 0.05)
        ..strokeCap = StrokeCap.round
        ..color = kind.ring.withValues(alpha: 0.4 * a);
      for (var i = 0; i < 3; i++) {
        final x = w * (0.3 + 0.2 * i);
        canvas.drawLine(
          Offset(x, -h * 0.04),
          Offset(x, -h * (0.18 + 0.05 * i)),
          streak,
        );
      }
    }

    _sprite(sway >= 0 ? 0 : 1).draw(
      canvas,
      Rect.fromLTWH(0, -bob, w, h),
      _palettes[kind]!,
      alpha: a,
    );
  }
}
