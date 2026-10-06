import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'depth_component.dart';
import 'perspective.dart';
import 'truck_sprites.dart';

/// Aspecto de un camión: colores de la chapa, la franja y la cabina.
enum TruckLook {
  /// Caja blanca sucia, franja roja y cabina colorada.
  white(
    body: Color(0xFFC9C4B4),
    light: Color(0xFFE4DFD0),
    dark: Color(0xFF8F8A7C),
    stripe: Color(0xFFC2452D),
    stripeDark: Color(0xFF7C2A1B),
    cab: Color(0xFFB5392B),
    cabRoof: Color(0xFF8E2B20),
  ),

  /// Caja azul desteñida, franja amarilla y cabina verde.
  blue(
    body: Color(0xFF4F7391),
    light: Color(0xFF7A9AB3),
    dark: Color(0xFF35516B),
    stripe: Color(0xFFE0B040),
    stripeDark: Color(0xFF9A7620),
    cab: Color(0xFF3F8F68),
    cabRoof: Color(0xFF2E6B4D),
  ),

  /// Caja oxidada, franja crema y cabina gris.
  rust(
    body: Color(0xFF9A5A3A),
    light: Color(0xFFBD7D55),
    dark: Color(0xFF6B3A24),
    stripe: Color(0xFFD9D2BF),
    stripeDark: Color(0xFF9C957F),
    cab: Color(0xFF5E6B73),
    cabRoof: Color(0xFF434D53),
  );

  const TruckLook({
    required this.body,
    required this.light,
    required this.dark,
    required this.stripe,
    required this.stripeDark,
    required this.cab,
    required this.cabRoof,
  });

  final Color body;
  final Color light;
  final Color dark;
  final Color stripe;
  final Color stripeDark;
  final Color cab;
  final Color cabRoof;

  /// Paleta de las letras del sprite de la cara trasera.
  Map<String, Color> get spritePalette => {
        'O': const Color(0xFF140E0C),
        'b': body,
        'l': light,
        'd': dark,
        's': stripe,
        'S': stripeDark,
        'r': const Color(0xFFD13B3B),
        'R': const Color(0xFF6B1616),
        'y': const Color(0xFFF2B13D),
        'D': const Color(0xFF2A2623),
        'g': const Color(0xFF8C8A84),
        'u': const Color(0xFF7A4423),
        'W': const Color(0xFFE4DFD0),
        'k': const Color(0xFF14110F),
      };
}

/// Camión estacionado en la ruta, como los trenes de Subway Surfers: se puede
/// **subir por la rampa** y correr por el techo (con diamantes), o esquivar.
///
/// Es un cuerpo largo, no una caja chata: ocupa un tramo de profundidad. Para
/// que ese tramo no se deforme al acercarse, todo se mide en `z = 1 + t` (la
/// inversa de la profundidad): el piso avanza multiplicando `z` por el mismo
/// factor en cada cuadro (ver [advance]), así que las distancias entre dos
/// puntos del camión —y entre el camión y sus diamantes— se conservan
/// exactamente como razones de `z`.
///
/// Orden de adelante (cerca del jugador) hacia atrás (lejos):
/// `rampa → cara trasera de la caja → techo de la caja → techo de la cabina`.
/// El jugador llega por la rampa, corre por la caja, baja un escalón a la
/// cabina y se cae por el final. La rampa y las alturas se miden en px sobre
/// la línea base (`t == 1`) y se escalan con la profundidad, igual que el
/// resto de los obstáculos.
///
/// El choque no se resuelve acá: [surfaceAt] dice a qué altura queda el techo
/// bajo los pies del jugador y `RunnerGame` decide si es un escalón que se
/// camina, un golpe o un salto al vacío.
class TruckComponent extends DepthComponent {
  TruckComponent({
    required double lane,
    required double speed,
    required Perspective perspective,
    this.boxLength = 0.55,
    this.hasRamp = true,
    this.look = TruckLook.white,
    double? startZ,
  })  : zFront = startZ ?? spawnZ,
        super(
          lane: lane,
          speed: speed,
          perspective: perspective,
          position: Vector2.zero(),
          size: Vector2(perspective.width, perspective.height),
          anchor: Anchor.topLeft,
        ) {
    syncGeometry();
  }

  /// Altura del techo de la caja, en px sobre la línea base (t = 1). Más
  /// alta que el techo del salto (~60 px): no se sube saltando, hay que usar
  /// la rampa.
  static const double roofHeight = 96;

  /// Altura del techo de la cabina: un escalón más abajo que la caja.
  static const double cabHeight = 60;

  /// Semiancho del camión en unidades de carril (cabe en un carril).
  static const double halfWidth = 0.42;

  /// Ancho de la rampa respecto del camión.
  static const double rampWidthFrac = 0.92;

  /// Largo de la rampa y de la cabina, en unidades `u = ln(z)` (distancia
  /// uniforme del mundo: ~0.2 u/s a velocidad base).
  static const double rampLength = 0.20;
  static const double cabLength = 0.16;

  /// `z` de nacimiento: igual que los obstáculos (t = 0.06).
  static const double spawnZ = 1.06;

  /// Largo de la caja en unidades `u`.
  final double boxLength;

  /// Si tiene rampa se puede subir; si no, es un muro que hay que esquivar.
  final bool hasRamp;

  final TruckLook look;

  /// `z` del extremo cercano de la caja (la cara trasera, donde empieza el
  /// techo). Crece multiplicándose cada cuadro.
  double zFront;

  /// true si en el frame anterior estaba bloqueando al jugador (un solo
  /// golpe por cruce).
  bool wasTouching = false;

  /// Distancias (en `u`, detrás de la cara trasera) a las que todavía falta
  /// sembrar un diamante del techo. `RunnerGame` los va soltando cuando cada
  /// punto del techo asoma por el horizonte.
  final List<double> pendingCoins = [];

  /// Cuántos diamantes llevaba el techo en total (para saber cuál es el del
  /// medio, el dorado).
  int plannedCoins = 0;

  // --- Geometría -------------------------------------------------------------

  /// `z` donde termina la caja y empieza la cabina.
  double get zBoxBack => zFront * exp(-boxLength);

  /// `z` del extremo lejano del camión (el final de la cabina).
  double get zBack => zBoxBack * exp(-cabLength);

  /// `z` del pie de la rampa (donde se apoya en el piso).
  double get zRampStart => hasRamp ? zFront * exp(rampLength) : zFront;

  /// Altura de pantalla de la línea de suelo de un `z` cualquiera.
  double yOf(double z) =>
      perspective.vanishY + max(0.0, z - 1) * perspective.corridorHeight;

  /// Carriles (-1, 0, 1) que ocupa.
  int get laneIndex => lane.round();

  @override
  bool get offScreen => yOf(zBack) > perspective.height + 8;

  /// Altura (px a la profundidad del jugador) del techo que hay bajo un
  /// jugador parado en `zp = 1 + t` y en [lanePos], o null si ahí no hay
  /// camión. [halfPlayer] es el semiancho del jugador en unidades de carril.
  double? surfaceAt(double zp, double lanePos, double halfPlayer) {
    final tp = zp - 1;
    final dx = (lanePos - lane).abs();
    if (zp >= zBack && zp <= zFront) {
      final inBox = zp >= zBoxBack;
      final half = inBox ? halfWidth : halfWidth * 0.92;
      if (dx > half + halfPlayer) return null;
      return (inBox ? roofHeight : cabHeight) * tp;
    }
    if (hasRamp && zp > zFront && zp <= zRampStart) {
      if (dx > halfWidth * rampWidthFrac + halfPlayer) return null;
      final s = log(zRampStart / zp) / rampLength; // 0 en el pie, 1 arriba
      return s.clamp(0.0, 1.0).toDouble() * roofHeight * tp;
    }
    return null;
  }

  // --- Ciclo -----------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);
    advance(dt);
    syncGeometry();
  }

  /// Mismo avance que el resto del piso (`z *= 1 + speed·dt / 2H`), pero sin
  /// el tope en la línea base: el camión es largo y su frente pasa de t = 1
  /// mientras el techo todavía está bajo los pies del jugador.
  @override
  void advance(double dt) {
    final h = perspective.corridorHeight;
    if (h <= 0) return;
    zFront *= 1 + speed * dt / (2 * h);
    baseY = perspective.vanishY + (zFront - 1) * h;
  }

  /// Ajusta el lienzo a la pantalla (se dibuja en coordenadas de pantalla) y
  /// la línea de suelo del frente.
  void syncGeometry() {
    position.setValues(0, 0);
    size.setValues(perspective.width, perspective.height);
    baseY = perspective.vanishY + (zFront - 1) * perspective.corridorHeight;
  }

  // --- Dibujo ----------------------------------------------------------------

  static final Map<TruckLook, Map<String, Color>> _spritePalettes = {
    for (final l in TruckLook.values) l: l.spritePalette,
  };

  static const Color _ink = Color(0xFF140E0C);
  static const Color _wood = Color(0xFFB98A57);
  static const Color _woodAlt = Color(0xFFA37646);
  static const Color _woodDark = Color(0xFF3B2614);

  @override
  void render(Canvas canvas) {
    final a = alpha;
    if (a <= 0) return;
    final p = perspective;
    final corridor = p.corridorHeight;
    final zF = zFront;
    if (corridor <= 0 || zF <= 1) return;

    double g(double z) => p.vanishY + max(0.0, z - 1) * corridor;
    double x(double l, double z) =>
        p.vanishX + l * p.baseWidth * 0.5 * max(0.0, z - 1);
    double yt(double z, double h) => g(z) - h * max(0.0, z - 1);
    Offset pt(double l, double z) => Offset(x(l, z), g(z));
    Offset pth(double l, double z, double h) => Offset(x(l, z), yt(z, h));

    final paint = Paint()..isAntiAlias = false;
    void fill(List<Offset> pts, Color c, [double al = 1]) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      path.close();
      paint
        ..style = PaintingStyle.fill
        ..color = c.withValues(alpha: al * a);
      canvas.drawPath(path, paint);
    }

    void line(Offset p0, Offset p1, Color c, double w, [double al = 1]) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, w)
        ..color = c.withValues(alpha: al * a);
      canvas.drawLine(p0, p1, paint);
    }

    void oval(Rect r, Color c, [double al = 1]) {
      paint
        ..style = PaintingStyle.fill
        ..color = c.withValues(alpha: al * a);
      canvas.drawOval(r, paint);
    }

    final zb = max(1.0, zBack);
    final zbb = max(1.0, zBoxBack);
    final zR = zRampStart;
    final logF = log(zF);

    // Sombra en el piso: apoya el camión (y la rampa) en la ruta.
    fill([
      pt(lane - halfWidth - 0.05, zb),
      pt(lane + halfWidth + 0.05, zb),
      pt(lane + halfWidth + 0.05, zR),
      pt(lane - halfWidth - 0.05, zR),
    ], Colors.black, 0.28);

    // La cara lateral que mira al centro de la ruta: solo se ve desde afuera
    // (un camión del carril central no muestra costados).
    final side = lane < -0.2 ? 1.0 : (lane > 0.2 ? -1.0 : 0.0);

    void sideBand(double sl, double z0, double z1, double h0, double h1,
        Color c, [double al = 1]) {
      fill([
        pth(sl, z0, h0),
        pth(sl, z1, h0),
        pth(sl, z1, h1),
        pth(sl, z0, h1),
      ], c, al);
    }

    // --- Cabina (la parte lejana): costado y techo.
    if (side != 0) {
      final sl = lane + side * halfWidth * 0.92;
      sideBand(sl, zb, zbb, 0, cabHeight, look.cab);
      final zw0 = zb * exp(cabLength * 0.12);
      final zw1 = zb * exp(cabLength * 0.62);
      sideBand(sl, zw0, zw1, 34, 52, const Color(0xFF9BC4D6));
      sideBand(sl, zw0, zw1, 34, 36, const Color(0xFF14110F), 0.6);
      sideBand(sl, zb, zbb, 0, 16, const Color(0xFF14110F));
    }
    fill([
      pth(lane - halfWidth * 0.92, zb, cabHeight),
      pth(lane + halfWidth * 0.92, zb, cabHeight),
      pth(lane + halfWidth * 0.92, zbb, cabHeight),
      pth(lane - halfWidth * 0.92, zbb, cabHeight),
    ], look.cabRoof);

    // --- Caja: costado con chasis, franja, costillas y ruedas.
    if (side != 0) {
      final sl = lane + side * halfWidth;
      sideBand(sl, zbb, zF, 0, roofHeight, look.dark);
      sideBand(sl, zbb, zF, 0, 18, const Color(0xFF14110F));
      sideBand(sl, zbb, zF, 52, 62, look.stripe);
      sideBand(sl, zbb, zF, 52, 53.5, look.stripeDark);
      final rib = Color.lerp(look.dark, Colors.black, 0.35)!;
      for (var u = logF - 0.05; u > logF - boxLength + 0.02; u -= 0.07) {
        final z = exp(u);
        line(pth(sl, z, 18), pth(sl, z, roofHeight), rib, 2 * (z - 1));
      }
      for (final k in const [0.10, 0.22, 0.46]) {
        if (k > boxLength - 0.03) continue;
        final z = zF * exp(-k);
        final r = 15 * (z - 1);
        if (r < 0.5) continue;
        final xs = x(sl, z);
        oval(Rect.fromLTWH(xs - r * 0.55, g(z) - r * 1.9, r * 1.1, r * 2.0),
            const Color(0xFF14110F));
        oval(Rect.fromLTWH(xs - r * 0.22, g(z) - r * 1.35, r * 0.44, r * 0.8),
            const Color(0xFF8C8A84));
      }
    }

    // --- Caja: techo, con barras transversales y dos largueros.
    fill([
      pth(lane - halfWidth, zbb, roofHeight),
      pth(lane + halfWidth, zbb, roofHeight),
      pth(lane + halfWidth, zF, roofHeight),
      pth(lane - halfWidth, zF, roofHeight),
    ], look.light);
    for (var u = logF - 0.05; u > logF - boxLength + 0.02; u -= 0.08) {
      final z = exp(u);
      line(pth(lane - halfWidth, z, roofHeight),
          pth(lane + halfWidth, z, roofHeight), look.dark, 3 * (z - 1), 0.8);
    }
    for (final off in const [-0.2, 0.2]) {
      line(pth(lane + off, zF, roofHeight), pth(lane + off, zbb, roofHeight),
          look.dark, 2.5 * (zF - 1), 0.6);
    }
    for (final edge in const [-halfWidth, halfWidth]) {
      line(pth(lane + edge, zF, roofHeight), pth(lane + edge, zbb, roofHeight),
          _ink, 1.2, 0.8);
    }

    // --- Cara trasera: las puertas, en pixel-art.
    TruckSprites.rear.draw(
      canvas,
      Rect.fromLTRB(
        x(lane - halfWidth, zF),
        yt(zF, roofHeight),
        x(lane + halfWidth, zF),
        g(zF),
      ),
      _spritePalettes[look]!,
      alpha: a,
    );

    // --- Rampa de tablones, con vigas laterales y bolsas de arena al pie.
    if (hasRamp) {
      const n = 8;
      const hs = halfWidth * rampWidthFrac;
      Offset rp(double s, double l) {
        final z = zF * exp((1 - s) * rampLength);
        return Offset(x(l, z), g(z) - s * roofHeight * (z - 1));
      }

      if (side != 0) {
        final sl = lane + side * hs;
        final wedge = <Offset>[for (var i = 0; i <= n; i++) rp(i / n, sl)];
        for (var i = n; i >= 0; i--) {
          wedge.add(pt(sl, zF * exp((1 - i / n) * rampLength)));
        }
        fill(wedge, Color.lerp(const Color(0xFF6B4A2E), Colors.black, 0.25)!);
      }
      for (var i = 0; i < n; i++) {
        final q0 = rp(i / n, lane - hs);
        final q1 = rp(i / n, lane + hs);
        fill([q0, q1, rp((i + 1) / n, lane + hs), rp((i + 1) / n, lane - hs)],
            i.isEven ? _wood : _woodAlt);
        line(q0, q1, _woodDark, 1.5);
      }
      for (final l in [lane - hs, lane + hs]) {
        line(rp(0, l), rp(1, l), _woodDark, max(2.0, 4 * (zF - 1)));
      }
      final r = 8 * (zR - 1);
      for (final l in [lane - hs * 0.7, lane + hs * 0.7]) {
        final foot = rp(0, l);
        oval(Rect.fromLTWH(foot.dx - r, foot.dy - r * 0.8, r * 2, r * 1.2),
            const Color(0xFFB39B6C));
      }
    }
  }
}
