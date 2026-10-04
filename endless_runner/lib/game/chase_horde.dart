import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'perspective.dart';
import 'zombie_sprites.dart';

/// Horda de zombies que persigue al corredor desde atrás (estilo Subway
/// Surfers).
///
/// El corredor siempre está en la misma fila de pantalla, así que "quedarse
/// atrás" no se mide en píxeles del jugador sino con una **distancia
/// normalizada** [gap] entre la horda y él:
///
///  - `gap == 1` → la horda va lejos: solo asoman unas cabezas por el borde
///    inferior de la pantalla,
///  - `gap == 0` → la horda llegó a la fila del corredor: **Game Over**.
///
/// Cómo se mueve la distancia (todo en unidades de `gap` por segundo):
///
///  - la horda **acelera cada [levelEvery] segundos** que el jugador
///    sobrevive ([level] sube y con él [speed]),
///  - el corredor se despega a un ritmo constante ([recovery]),
///  - tropezar con un obstáculo (perder una vida) deja a la horda más cerca
///    ([stumblePenalty]) y levantar diamantes la aleja un poco.
///
/// Los primeros niveles la horda va más lenta que la fuga del corredor (la
/// distancia se recupera sola); a partir del nivel 5 se acerca aunque no
/// haya errores, y el juego se vuelve una carrera contra el reloj.
///
/// Esta clase no depende de Flame: el estado es puro (testeable sin motor) y
/// el dibujo ([render]) solo necesita un [Canvas] y la [Perspective].
class ChaseHorde {
  // --- Tuneo ---------------------------------------------------------------

  /// Distancia al arrancar la partida: la horda ya se ve acechando.
  static const double startGap = 0.75;

  /// Distancia máxima (horda al borde de la pantalla).
  static const double maxGap = 1.0;

  /// Segundos de supervivencia por cada nivel de presión.
  static const double levelEvery = 10;

  /// Velocidad de la horda en el nivel 0 (distancia/seg).
  static const double baseSpeed = 0.012;

  /// Velocidad que suma la horda por cada nivel.
  static const double speedPerLevel = 0.004;

  /// Tope de velocidad de la horda.
  static const double maxSpeed = 0.06;

  /// Ritmo al que el corredor se despega de la horda (distancia/seg).
  static const double recovery = 0.030;

  /// Distancia que se pierde al tropezar (perder una vida).
  static const double stumblePenalty = 0.30;

  /// Distancia que se gana por cada diamante recogido.
  static const double pickupRelief = 0.012;

  /// Tope de lo que puede alejar un solo pickup (monedas de valor alto).
  static const double maxPickupRelief = 0.04;

  /// Por debajo de esta distancia la horda se considera encima: el dibujo
  /// pulsa en rojo para avisar.
  static const double dangerGap = 0.25;

  // --- Estado --------------------------------------------------------------

  /// Distancia actual a la horda (0 = atrapado, 1 = lejos).
  double gap = startGap;

  /// Segundos de partida sobrevividos con la horda activa.
  double elapsed = 0;

  /// Nivel de presión: sube cada [levelEvery] segundos.
  int level = 0;

  /// true cuando la horda alcanzó al corredor. Es "pegajoso": una vez
  /// atrapado, la recuperación del mismo frame no lo deshace.
  bool caught = false;

  double _phase = 0;

  /// Velocidad de acercamiento de la horda en el nivel actual.
  double get speed => min(maxSpeed, baseSpeed + speedPerLevel * level);

  /// Distancia que gana o pierde por segundo el jugador (negativo = la horda
  /// lo alcanza).
  double get netRecovery => recovery - speed;

  /// 0 (lejos) .. 1 (encima).
  double get danger => 1 - gap.clamp(0.0, maxGap).toDouble();

  /// true cuando la horda está a un paso.
  bool get inDanger => gap <= dangerGap;

  /// Avanza la horda [dt] segundos. Devuelve true si en este paso subió de
  /// nivel (el juego lo usa para avisar con un destello).
  bool update(double dt) {
    elapsed += dt;
    _phase += dt;

    final newLevel = (elapsed / levelEvery).floor();
    final leveledUp = newLevel > level;
    if (leveledUp) level = newLevel;

    gap = (gap + netRecovery * dt).clamp(0.0, maxGap).toDouble();
    if (gap <= 0) caught = true;
    return leveledUp;
  }

  /// El corredor tropezó: la horda gana terreno de golpe.
  void stumble() {
    gap = (gap - stumblePenalty).clamp(0.0, maxGap).toDouble();
    if (gap <= 0) caught = true;
  }

  /// El corredor levantó un pickup de [value] diamantes: se despega un poco.
  void relieve(int value) {
    final amount = min(maxPickupRelief, pickupRelief * max(1, value));
    gap = min(maxGap, gap + amount);
  }

  /// Distancia a la que queda la horda tras revivir: da aire para reaccionar.
  static const double reviveGap = 0.65;

  /// El jugador revivió: la horda deja de atraparlo y retrocede, pero conserva
  /// su nivel de velocidad (revivir no borra la dificultad alcanzada).
  void revive() {
    caught = false;
    gap = max(gap, reviveGap);
  }

  /// Vuelve al estado de inicio de partida.
  void reset() {
    gap = startGap;
    elapsed = 0;
    level = 0;
    caught = false;
    _phase = 0;
  }

  // --- Dibujo --------------------------------------------------------------

  /// Cuánto más grande se ve la horda cuando está encima (1 = tamaño base).
  /// Es lo que da la sensación de que "crece" al acercarse.
  static const double maxLooming = 2.4;

  /// Alto de un zombi en la línea del corredor sin el factor de cercanía.
  static const double baseHeight = 60;

  /// Posición lateral (-1..1 del corredor) de cada zombi, fila por fila. La
  /// fila 0 es la de adelante (la que primero alcanza al corredor).
  static const List<List<double>> _rows = [
    [-0.78, -0.39, 0.0, 0.39, 0.78],
    [-0.95, -0.58, -0.2, 0.2, 0.58, 0.95],
    [-0.7, -0.3, 0.3, 0.7],
  ];

  static const Color _skin = Color(0xFF7F9C68);
  static const Color _fog = Color(0xFF3A0B0B);
  static const List<Color> _hairs = [
    Color(0xFF2B2018),
    Color(0xFF3A3A3A),
    Color(0xFF5A4630),
    Color(0xFF1A1A1E),
  ];
  static const List<Color> _clothes = [
    Color(0xFF5B4A6B),
    Color(0xFF3E4C63),
    Color(0xFF6B4A3E),
    Color(0xFF4A5A44),
    Color(0xFF5E5E5E),
  ];
  static const List<Color> _pants = [
    Color(0xFF2B3342),
    Color(0xFF3A3328),
    Color(0xFF23262C),
  ];

  /// Y de pantalla del frente de la horda (los pies de la fila de adelante)
  /// para una distancia [g] dada. Con `g == 0` coincide con los pies del
  /// corredor: esa es la "línea de Game Over".
  double frontFeetY(Perspective p, double playerFeetY, [double? g]) {
    final gg = (g ?? gap).clamp(0.0, maxGap).toDouble();
    final h = zombieHeight(p, playerFeetY, gg);
    final farFeetY = p.height + h * 0.5;
    return playerFeetY + (farFeetY - playerFeetY) * gg;
  }

  /// Alto de un zombi de la fila de adelante: crece al acercarse.
  double zombieHeight(Perspective p, double playerFeetY, [double? g]) {
    final gg = (g ?? gap).clamp(0.0, maxGap).toDouble();
    final looming = maxLooming + (1.0 - maxLooming) * gg;
    return baseHeight * looming * p.tAtY(playerFeetY);
  }

  /// Dibuja la horda y la niebla roja de la zona de peligro. Se llama antes
  /// de los componentes: el corredor y los obstáculos quedan encima.
  void render(Canvas canvas, Perspective p, {required double playerFeetY}) {
    if (p.width <= 0 || p.height <= 0) return;

    final g = gap.clamp(0.0, maxGap).toDouble();
    final h = zombieHeight(p, playerFeetY, g);
    final frontY = frontFeetY(p, playerFeetY, g);

    // Niebla de la zona de Game Over: oscurece el borde inferior y pulsa
    // cuando la horda está encima.
    final fogTop = frontY - h * 1.15;
    if (fogTop < p.height) {
      final pulse = inDanger ? 0.5 + 0.5 * sin(_phase * 10) : 0.0;
      final alpha =
          (0.3 + 0.35 * danger + 0.2 * pulse).clamp(0.0, 0.9).toDouble();
      final rect = Rect.fromLTRB(0, fogTop, p.width, p.height);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, fogTop),
            Offset(0, p.height),
            [_fog.withValues(alpha: 0), _fog.withValues(alpha: alpha)],
          ),
      );
    }

    // Filas de atrás hacia adelante en pantalla: las de abajo están más cerca
    // de la cámara y tapan a las de arriba.
    for (var row = 0; row < _rows.length; row++) {
      final feetY = frontY + row * h * 0.42;
      final rowHeight = h * (1 + 0.08 * row);
      if (feetY - rowHeight > p.height) continue;

      final half = p.halfWidthAtT(p.tAtY(feetY)) * 0.98;
      final lanes = _rows[row];
      for (var i = 0; i < lanes.length; i++) {
        _drawZombie(
          canvas,
          cx: p.vanishX + lanes[i] * half,
          feetY: feetY,
          h: rowHeight,
          row: row,
          index: i,
        );
      }
    }
  }

  /// Número pseudoaleatorio estable en [0, 1) a partir de [n]: cada zombi de la
  /// horda conserva su altura, ropa y peinado entre cuadros sin crear un
  /// `Random` por figura.
  static double _unit(int n) => (sin(n * 12.9898) * 43758.5453).abs() % 1.0;

  /// Paleta de cada zombi de la horda (clave: su semilla), armada una vez.
  static final Map<int, Map<String, Color>> _palettes = {};

  /// Un zombi visto de espaldas, en pixel-art de 8 bits como el corredor: corre
  /// encorvado hacia el jugador con los brazos arriba. Cada uno es distinto
  /// (semilla = fila e índice): altura, estilo (camiseta, campera, capucha o
  /// torso al aire), peinado, colores de ropa y pelo. Las filas de atrás se
  /// oscurecen para meterse en la niebla.
  void _drawZombie(
    Canvas canvas, {
    required double cx,
    required double feetY,
    required double h,
    required int row,
    required int index,
  }) {
    final seed = row * 7 + index;
    h = h * (0.92 + 0.16 * _unit(seed * 3 + 1));

    final style = (seed * 5 + index) % 4;
    final variants = ZombieSprites.back[style];
    final variant = variants[(seed * 3 + index) % variants.length];
    final sprite = variant[sin(_phase * 7 + seed * 2.3) >= 0 ? 0 : 1];
    final w = h * sprite.width / sprite.height;
    final bob = sin(_phase * 9 + seed * 1.7).abs() * h * 0.03;

    // Sombra en el piso.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, feetY),
        width: w * 1.4,
        height: h * 0.1,
      ),
      Paint()..color = const Color(0x66000000),
    );

    final palette = _palettes.putIfAbsent(
      seed,
      () => ZombiePalette.build(
        skin: _skin,
        clothes: _clothes[seed % _clothes.length],
        eyes: const Color(0xFFFFFFFF),
        hair: _hairs[seed % _hairs.length],
        pants: _pants[(seed ~/ 2) % _pants.length],
        shade: (row * 0.14).clamp(0.0, 1.0).toDouble(),
      ),
    );
    sprite.draw(
      canvas,
      Rect.fromLTWH(cx - w * 0.5, feetY - bob - h, w, h),
      palette,
    );
  }
}
