import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'depth_component.dart';
import 'perspective.dart';

/// Patrón en el que se agrupan las monedas.
///
/// Nunca se generan monedas sueltas: siempre en tanda, para que el jugador
/// pueda *seguir* la línea y decidir si se manda el gesto completo o se queda
/// con la mitad.
enum CoinPattern {
  /// Línea recta en un carril: barrido simple.
  line,

  /// Cruce suave de un borde al otro: premia el cambio de carril.
  arc,

  /// Escalera que alterna cada cuatro monedas: hay que decidir hasta dónde.
  zigzag,

  /// Nube alta: **hay que saltar** (parado no alcanza).
  high;

  /// Anclajes de carril válidos para este patrón. El anclaje más extremo más
  /// el barrido del patrón nunca supera ±1, así todas las monedas caen dentro
  /// del corredor.
  List<double> get anchorCandidates => switch (this) {
        line || high => const [-1.0, 0.0, 1.0],
        arc || zigzag => const [-0.5, 0.0, 0.5],
      };
}

/// Moneda proyectada en perspectiva 2.5D (hereda la ley de movimiento y la
/// colisión de [DepthComponent]).
///
/// Su banda de altura decide el gesto: en el suelo se recoge corriendo y en
/// la variante [elevated] (56..82 px sobre el suelo) hace falta saltar: la
/// caja parada llega apenas hasta 34 px.
class CoinComponent extends DepthComponent {
  CoinComponent({
    required super.lane,
    required super.perspective,
    required super.speed,
    required super.spawnT,
    this.elevated = false,
    this.value = 1,
  }) : super(
          position: Vector2.zero(),
          size: Vector2.all(1),
          anchor: Anchor.topLeft,
        ) {
    syncGeometry();
  }

  /// Tamaño de la moneda en unidades de la línea base (t = 1).
  static const double worldSize = 26;

  /// Banda más baja de una moneda elevada: el techo del salto (~60 px) la
  /// alcanza, la caja parada (0..34) no.
  static const double elevatedBandMin = 56;

  /// true = flota y hay que saltar para recogerla.
  final bool elevated;

  /// Diamantes que da al recogerla (1 a 5). Las de 3 o más se dibujan doradas.
  final int value;

  bool get isGolden => value >= 3;

  /// Perdona ~60 % del ancho de la moneda en X: con el jugador a mitad de un
  /// cambio de carril la caja (24 px) apenas rozaba la moneda (26 px).
  @override
  double get lateralSlack => size.x * 0.6;

  /// Borde inferior de la caja sobre el propio suelo (en px de pantalla).
  double _bandMinPx = 0;

  void syncGeometry() {
    final s = depthScale;
    final w = worldSize * s;
    _bandMinPx = (elevated ? elevatedBandMin : 0) * s;
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
    syncGeometry();
  }

  // --- Dibujo ----------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    final a = alpha;
    if (a <= 0) return;
    final w = size.x;
    final h = size.y;
    final groundY = h + _bandMinPx; // línea de suelo en coordenadas locales

    // Sombra en el piso: separa la moneda del suelo y hace visible el salto.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, groundY),
        width: w * 0.8,
        height: (groundY * 0.05 + 2).clamp(2.0, 9.0),
      ),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.22 * a),
    );

    // Gema (rombo) con contorno para que resalte en los dos temas.
    final gem = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w, h * 0.36)
      ..lineTo(w * 0.5, h)
      ..lineTo(0, h * 0.36)
      ..close();
    final gemColor = isGolden ? _goldGem : _gem;
    final shineColor = isGolden ? _goldShine : _shine;
    final outlineColor = isGolden ? _goldOutline : _outline;
    canvas.drawPath(
      gem,
      Paint()
        ..color = outlineColor.withValues(alpha: 0.7 * a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (w * 0.06).clamp(0.8, 3.0),
    );
    canvas.drawPath(gem, Paint()..color = gemColor.withValues(alpha: a));

    // Faceta clara arriba-izquierda + brillo puntual.
    final facet = Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.5, h * 0.36)
      ..lineTo(0, h * 0.36)
      ..close();
    canvas.drawPath(facet, Paint()..color = shineColor.withValues(alpha: 0.5 * a));
    canvas.drawCircle(
      Offset(w * 0.36, h * 0.2),
      (w * 0.07).clamp(0.6, 3.0),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.75 * a),
    );
  }

  static const Color _gem = Color(0xFF46DDF2);
  static const Color _shine = Color(0xFFC7F7FF);
  static const Color _outline = Color(0xFF0F3B4C);
  static const Color _goldGem = Color(0xFFFFC53D);
  static const Color _goldShine = Color(0xFFFFF0B3);
  static const Color _goldOutline = Color(0xFF5A3B00);
}

/// Genera las monedas de un [pattern] ancladas en [anchorLane].
///
/// Cada moneda nace en su propia profundidad (`spawnT`), dentro de la zona en
/// la que todavía aparece desvanecida, de modo que el patrón entra en escena
/// sin "pops" y se estira solo a medida que se acerca al jugador (la ley de
/// perspectiva hace que las monedas distantes se separen más).
///
/// El `spawnT` de arranque (0.13) es a propósito más profundo que el de los
/// obstáculos (0.06): así el patrón nace ~36 px por delante de la línea en la
/// que aparece un obstáculo nuevo. Si no, un obstáculo spawneado *después* del
/// patrón arrancaría en la misma profundidad y viajaría pegado a la cola de
/// monedas (la distancia entre dos actores solo crece, así que una vez abierto
/// ese hueco ya no se cierra).
///
/// Los carriles finales siempre quedan dentro de ±1: ver
/// [CoinPattern.anchorCandidates].
List<CoinComponent> buildCoinPattern({
  required CoinPattern pattern,
  required Perspective perspective,
  required double speed,
  required double anchorLane,
}) {
  // Igual que el spawn de obstáculos (0.06) pero corrido: ver doc arriba.
  const start = 0.13;

  CoinComponent coin(
    double lane,
    double spawnT, {
    required bool elevated,
    int value = 1,
  }) =>
      CoinComponent(
        lane: lane.clamp(-1.0, 1.0),
        perspective: perspective,
        speed: speed,
        spawnT: spawnT,
        elevated: elevated,
        value: value,
      );

  switch (pattern) {
    case CoinPattern.line:
      // 7 monedas en fila, una tras otra.
      return [
        for (var i = 0; i < 7; i++)
          coin(anchorLane, start + i * 0.012, elevated: false),
      ];
    case CoinPattern.arc:
      // Barrido de -0.45 a +0.45 carriles sobre el anclaje.
      return [
        for (var i = 0; i < 7; i++)
          coin(
            anchorLane + (i / 6 - 0.5) * 0.9,
            start + i * 0.014,
            elevated: false,
            value: i == 3 ? 3 : 1, // la del medio es dorada
          ),
      ];
    case CoinPattern.zigzag:
      // Bloques de 4 monedas alternando ±0.5 carril sobre el anclaje.
      return [
        for (var i = 0; i < 10; i++)
          coin(
            anchorLane + ((i ~/ 4).isEven ? -0.5 : 0.5),
            start + i * 0.012,
            elevated: false,
          ),
      ];
    case CoinPattern.high:
      // Nube alta: una sola parábola de salto las recoge todas. Vale más por
      // el riesgo de saltar: 2 cada una y la del centro, dorada, 5.
      return [
        for (var i = 0; i < 5; i++)
          coin(
            anchorLane,
            start + i * 0.014,
            elevated: true,
            value: i == 2 ? 5 : 2,
          ),
      ];
  }
}
