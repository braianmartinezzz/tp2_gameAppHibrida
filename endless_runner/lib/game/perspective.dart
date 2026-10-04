/// Modelo de perspectiva compartido por el mapa y los obstáculos 2.5D.
///
/// Toda la geometría del corredor sale de una única proyección con
/// profundidad normalizada `t`:
///
///  - `t == 0` → punto de fuga / horizonte (todo converge ahí)
///  - `t == 1` → línea base del corredor (borde inferior de la pantalla)
///
/// El carril también está normalizado: `lane == -1` y `lane == 1` marcan los
/// bordes del corredor en la línea base. La posición X de un objeto a cualquier
/// profundidad se obtiene interpolando hacia el punto de fuga, de modo que un
/// obstáculo lejano nace en el centro del corredor y se "abre" hacia su carril
/// a medida que se acerca al jugador. La escala sigue la misma ley: un objeto
/// lejos es chico y crece proporcionalmente a `t`.
class Perspective {
  const Perspective({required this.width, required this.height});

  final double width;
  final double height;

  /// Altura del horizonte / punto de fuga (donde vive `t == 0`).
  double get vanishY => height * 0.14;

  /// Altura en pantalla del corredor: desde el horizonte hasta la base.
  double get corridorHeight => height - vanishY;

  /// Coordenada X del punto de fuga (centrada).
  double get vanishX => width * 0.5;

  /// Bordes del corredor en la línea base (`t == 1`).
  ///
  /// Antes 0.04 / 0.96 (el jugador corría pegado al borde de la pantalla).
  /// Con 0.12 / 0.88 queda asfalto, hombro y arena visibles a cada lado.
  double get baseLeftX => width * 0.12;
  double get baseRightX => width * 0.88;

  /// Ancho completo del corredor en la línea base.
  double get baseWidth => baseRightX - baseLeftX;

  /// Profundidad normalada (0..1) de una altura de pantalla.
  double tAtY(double y) => ((y - vanishY) / corridorHeight).clamp(0.0, 1.0);

  /// Altura de pantalla de una profundidad normalizada.
  double yAtT(double t) => vanishY + t.clamp(0.0, 1.0) * corridorHeight;

  /// Mitad de ancho del corredor a una profundidad.
  double halfWidthAtT(double t) => baseWidth * 0.5 * t.clamp(0.0, 1.0);

  /// X de un carril normalizado a una profundidad.
  ///
  /// En el horizonte todos los carriles colapsan en `vanishX`; en la línea
  /// base ocupan el ancho completo del corredor.
  double xAtT(double lane, double t) =>
      vanishX + lane.clamp(-1.0, 1.0) * halfWidthAtT(t);

  /// Escala relativa de un objeto a una profundidad (1 en la línea base).
  double scaleAtT(double t) => t.clamp(0.0, 1.0);

  /// Mantiene una X dentro de los bordes del corredor a la altura `y`.
  double clampToCorridor(double x, double y) {
    final t = tAtY(y);
    return x.clamp(xAtT(-1, t), xAtT(1, t));
  }
}
