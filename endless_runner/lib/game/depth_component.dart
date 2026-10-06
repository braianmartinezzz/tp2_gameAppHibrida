import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'perspective.dart';
import 'player_component.dart';

/// Actor que viaja por el corredor en perspectiva 2.5D.
///
/// Es la base de todo lo que se mueve con el piso (obstáculos, monedas y
/// power-ups) y concentra las dos cosas que tienen que compartir:
///
///  - **La ley de movimiento.** La línea de suelo `baseY` es la fuente de
///    verdad de la profundidad y avanza con la aceleración de perspectiva
///    `dz = speed * (0.5 + 0.5 t)`, la misma que usan las rayas del piso
///    (`t = 1/z`), así todos los actores quedan sincronizados con el suelo.
///
///  - **La colisión por fila + carril + altura.** Las alturas se miden
///    *cada una sobre su propio suelo* (la del actor en pantalla, la del
///    jugador como `jumpY .. jumpY + bodyHeight`), de modo que un objeto
///    lejano no "sube" en pantalla al acercarse — ese fue el golpe fantasma
///    que se corrigió en la Fase 1.
abstract class DepthComponent extends PositionComponent {
  DepthComponent({
    required this.lane,
    required this.perspective,
    required this.speed,
    required Vector2 position,
    required Vector2 size,
    required Anchor anchor,
    this.spawnT = 0.06,
  })  : baseY = perspective.yAtT(spawnT),
        super(position: position, size: size, anchor: anchor);

  /// Profundidad normalada a la que aparece (lejos, apenas bajo el horizonte).
  final double spawnT;

  /// Recorrido de la fundida de aparición en unidades de `t`: cada actor nace
  /// transparente en su propia [spawnT] y se solidifica al acercarse, así un
  /// patrón que cubre varias profundidades no aparece "de golpe".
  static const double fadeSpan = 0.14;

  /// Tolerancia de la fila: un actor cuenta como "en la fila del jugador"
  /// dentro de ±14 px de su línea de suelo. Da ~3 frames de ventana incluso
  /// a máxima velocidad (620 px/s).
  static const double depthMargin = 14;

  /// Carril normalizado: -1 = borde izquierdo del corredor, +1 = derecho.
  double lane;

  /// Geometría de perspectiva vigente (la refresca el juego en cada resize).
  Perspective perspective;

  /// Velocidad en px/s sobre la línea base. El juego la actualiza cada frame.
  double speed;

  /// Línea de suelo del actor en pantalla (la profundidad, en px).
  double baseY;

  /// Profundidad normalada (0..1).
  double get t => perspective.tAtY(baseY);

  /// Escala del actor a su profundidad (1 en la línea base). Se llama
  /// [depthScale] para no pisar el `scale` (Vector2) de [PositionComponent].
  double get depthScale => perspective.scaleAtT(t);

  /// 0..1: nace transparente en [spawnT] y se solidifica con la bruma.
  ///
  /// El `t` sale de una ida y vuelta `t → y → t` con coma flotante, así que
  /// al nacer el resultado puede ser un residuo del orden de 1e-16 en vez de
  /// 0 exacto. Ese residuo no se ve, pero rompe el contrato de "nace con
  /// alpha 0" (y hace pintar el primer frame a opacidad casi nula): se trunca
  /// a 0 antes de usarlo.
  double get alpha {
    final value = (t - spawnT) / fadeSpan;
    if (value < 1e-9) return 0;
    return value.clamp(0.0, 1.0);
  }

  /// Centro en X del carril a la profundidad actual.
  double get centerX => perspective.xAtT(lane, t);

  /// Mitad del ancho del actor expresado en unidades de carril: sirve para
  /// saber si dos actores se pisan lateralmente (chocan en X) sin convertir
  /// nada a mano.
  double get laneHalfSpan {
    final halfWidth = perspective.halfWidthAtT(t);
    if (halfWidth <= 0) return 0;
    return (size.x * 0.5) / halfWidth;
  }

  // Tramo de profundidad recorrido en el último [advance]. Sirve para la
  // colisión barrida: si un frame es largo, el actor puede cruzar toda la
  // fila del jugador sin que ningún frame lo vea dentro de ±[depthMargin].
  double _sweepFrom = double.nan;
  double _sweepTo = double.nan;

  /// Avanza un paso con la aceleración de perspectiva.
  void advance(double dt) {
    final from = baseY;
    baseY += speed * (0.5 + 0.5 * t) * dt;
    _sweepFrom = from;
    _sweepTo = baseY;
  }

  /// true si el tramo recorrido en el último frame (más el margen) toca la
  /// fila [feetY]. Si alguien movió [baseY] a mano (tests, respawns) el tramo
  /// guardado ya no vale y se usa solo la posición actual.
  bool reachesRow(double feetY) {
    final from = (baseY == _sweepTo) ? _sweepFrom : baseY;
    final lo = (from < baseY ? from : baseY) - depthMargin;
    final hi = (from > baseY ? from : baseY) + depthMargin;
    return feetY >= lo && feetY <= hi;
  }

  /// Rect de la caja en pantalla (borde superior izquierdo = `position`).
  Rect get hitBox => Rect.fromLTWH(position.x, position.y, size.x, size.y);

  /// true cuando la caja quedó completamente fuera de la pantalla.
  bool get offScreen => baseY > perspective.height;

  // --- Colisión --------------------------------------------------------------

  /// Colisión con el [player] usando la caja en pantalla como banda de
  /// altura: la banda sobre el suelo sale de la distancia entre [baseY] y el
  /// borde de la caja, así sirve igual para un obstáculo, una moneda o un
  /// power-up sin repetir la cuenta en cada actor.
  bool collidesWith(PlayerComponent player) => overlapsPlayer(
        player,
        bandMin: baseY - (position.y + size.y),
        bandMax: baseY - position.y,
        lateralSlack: lateralSlack,
      );

  /// Holgura lateral (px) que se le suma a la caja del jugador al chequear el
  /// solape en X. 0 para obstáculos (golpe exacto); las monedas la
  /// sobreescriben para que no se escapen por unos píxeles mientras el
  /// jugador está cambiando de carril.
  double get lateralSlack => 0;

  /// Colisión con el [player] en tres pasos:
  ///
  ///  1. **fila**: la línea de suelo del actor debe estar dentro de
  ///     ±[depthMargin] de los pies del jugador (si no, está lejos),
  ///  2. **carril**: solape en X (la profundidad ya coincide),
  ///  3. **altura**: `[bandMin, bandMax]` en px sobre el suelo del actor vs
  ///     `[jumpY, jumpY + bodyHeight]` del jugador.
  ///
  /// Devuelve false mientras el actor todavía está en su fundida ([alpha] 0).
  bool overlapsPlayer(
    PlayerComponent player, {
    required double bandMin,
    required double bandMax,
    double lateralSlack = 0,
  }) {
    if (alpha <= 0) return false;
    // Fila barrida: cuenta el tramo recorrido en el frame, no solo el punto.
    if (!reachesRow(player.groundFeetY)) return false;

    final a = hitBox;
    final b = player.hitBox;
    if (a.left >= b.right + lateralSlack || a.right <= b.left - lateralSlack) {
      return false;
    }

    final playerBottom = player.jumpY;
    final playerTop = player.jumpY + player.bodyHeight;
    return playerTop > bandMin && bandMax > playerBottom;
  }
}
