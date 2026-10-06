import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart' show AppColors;
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
///  7. bruma de distancia que suaviza el horizonte,
///  8. ambientación de fin del mundo: sol sucio velado por el humo, cuervos
///     de día, estrella fugaz de noche, pirámides lejanas, resplandor de
///     incendios al pie de las columnas de humo (el naranja brasa de la
///     marca), nubes de ceniza, cordones gastados en la orilla del asfalto,
///     matas, piedritas y huesos junto al camino,
///  9. **detalles del asfalto** (grietas, manchas de aceite, frenadas, arena
///     que invade la ruta y parches), que viajan en coordenada de mundo,
/// 10. **biomas por distancia**: desierto → ruinas → cañón → desierto...
///     ([biomeAt]). Cambian la paleta (mezcla suave) y los props que nacen
///     al fondo: postes, autos abandonados, barandas y edificios rotos en
///     las ruinas; pilares de roca en el cañón.
///
/// Mantiene su propio estado de animación (tiempo, profundidad de rayas,
/// manchones y props) para que el mapa avance incluso sin obstáculos.
class MapRenderer {
  MapRenderer() {
    _props.addAll(_seedProps());
    _sortPropsFarToNear();
    _bits.addAll(_seedBits());
    _sortBitsFarToNear();
    _decals.addAll(_seedDecals());
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

  /// Tipos de prop (`style % _kindStride`):
  ///   0 cactus, 1 roca, 2 arbusto seco, 3 meseta, 4 cartel de ruta (desierto),
  ///   5 poste de luz, 6 auto abandonado, 7 guardarraíl, 8 edificio en ruinas,
  ///   9 alambrado roto (ruinas) y 10 pilar de roca (cañón).
  ///
  /// El paso del código de estilo es 15, múltiplo de 5: así `style % 5` sigue
  /// devolviendo el tipo original (0..4) de los props del desierto.
  static const int _kindStride = 15;

  /// Tipo por posición en la carretera, por bioma: alterna siluetas a lo
  /// largo del recorrido y los dos lados arrancan en puntos distintos del
  /// patrón.
  static const List<List<int>> _kindsByBiome = [
    [0, 3, 1, 4, 2, 0, 3], // desierto
    [8, 5, 6, 7, 4, 9, 5], // ruinas
    [10, 3, 1, 10, 2, 3, 4], // cañón
  ];

  /// Ancho del rectángulo base por tipo (sobre el ancho del corredor).
  static const List<double> _kindWidthFrac = [
    0.22, 0.34, 0.30, 0.46, 0.24, // desierto
    0.10, 0.30, 0.40, 0.50, 0.34, 0.26, // poste, auto, baranda, edificio, alambrado, pilar
  ];

  /// Alto por tipo (sobre la altura de la pantalla): la meseta manda y el
  /// arbusto se queda bajo.
  static const List<double> _kindHeightFrac = [
    0.60, 0.40, 0.32, 1.0, 0.70,
    0.62, 0.26, 0.16, 0.85, 0.22, 0.95,
  ];

  /// Separación extra desde el hueco mínimo por tipo: el cartel pega a la
  /// ruta y la meseta se queda más atrás.
  static const List<double> _kindLateral = [
    0.2, 0.5, 0.7, 0.35, 0.0,
    0.1, 0.5, 0.0, 0.9, 0.3, 0.8,
  ];

  // --- Biomas ----------------------------------------------------------------
  /// Largo de cada bioma en px de mundo recorridos (a 260-600 px/s son unos
  /// 20-30 s) y tramo final en el que se mezcla con el siguiente.
  static const double biomeLength = 9000;
  static const double biomeBlend = 1500;

  /// Distancia recorrida (px de mundo) desde el último [resetRun].
  double _distance = 0;

  @visibleForTesting
  double get distance => _distance;

  /// Bioma actual y el que viene, con el grado de mezcla (0..1, suavizado).
  /// Los biomas rotan desierto → ruinas → cañón → desierto...
  static ({Biome from, Biome to, double mix}) biomeAt(double distance) {
    final d = max(0.0, distance);
    final index = (d / biomeLength).floor();
    final into = d - index * biomeLength;
    final blendStart = biomeLength - biomeBlend;
    final raw = into <= blendStart
        ? 0.0
        : ((into - blendStart) / biomeBlend).clamp(0.0, 1.0).toDouble();
    return (
      from: Biome.values[index % Biome.values.length],
      to: Biome.values[(index + 1) % Biome.values.length],
      mix: raw * raw * (3 - 2 * raw), // smoothstep
    );
  }

  /// Bioma vigente (el que más pesa en la mezcla actual).
  Biome get currentBiome {
    final b = biomeAt(_distance);
    return b.mix >= 0.5 ? b.to : b.from;
  }

  /// Bioma al que pertenecen los props y detalles que nacen ahora al fondo:
  /// durante la mezcla ya son del siguiente, así cuando termina el cambio de
  /// colores los props ya coinciden con el paisaje.
  Biome get _spawnBiome {
    final b = biomeAt(_distance);
    return b.mix > 0 ? b.to : b.from;
  }

  /// Vuelve al desierto y a los props iniciales (nueva partida).
  void resetRun() {
    _distance = 0;
    _propSerial = 0;
    _decalSerial = 0;
    _props
      ..clear()
      ..addAll(_seedProps());
    _sortPropsFarToNear();
    _decals
      ..clear()
      ..addAll(_seedDecals());
  }

  int _propSerial = 0;

  /// Da a [prop] el aspecto del siguiente tipo del bioma que nace.
  void _recycleLook(SideProp prop) {
    final kinds = _kindsByBiome[_spawnBiome.index];
    final kind = kinds[(_propSerial + (prop.side > 0 ? 3 : 0)) % kinds.length];
    prop.widthFrac = _kindWidthFrac[kind];
    prop.heightFrac = _kindHeightFrac[kind];
    prop.lateralFrac = _kindLateral[kind];
    prop.style = (_propSerial + 1) * _kindStride + kind;
    _propSerial++;
  }

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
        final kinds = _kindsByBiome[Biome.desert.index];
        final kind = kinds[(i + (side > 0 ? 3 : 0)) % kinds.length];
        list.add(
          SideProp(
            side: side,
            z: _propZMin + k * _propZStep,
            widthFrac: _kindWidthFrac[kind],
            heightFrac: _kindHeightFrac[kind],
            lateralFrac: _kindLateral[kind],
            // `style % _kindStride` es el tipo; el resto de la semilla varía
            // el tono entre props del mismo tipo.
            style: i * _kindStride + kind,
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

  // --- Detalles de suelo (matas, piedritas, flores, cactus bebé) -----------
  /// Cantidad de detalles por lado. Son chicos y quedan más lejos de la ruta
  /// que los props grandes; comparten su ley de movimiento y su reciclaje.
  static const int _bitCount = 9;
  static const int _bitKinds = 4;

  /// Separación lateral de cada detalle (misma unidad que `lateralFrac`).
  static const List<double> _bitLateral = [
    1.5,
    3.2,
    2.1,
    4.6,
    1.0,
    3.6,
    5.2,
    2.6,
    4.0,
  ];
  static const List<double> _bitWidthFrac = [0.07, 0.10, 0.05, 0.07];
  static const List<double> _bitHeightFrac = [0.05, 0.03, 0.065, 0.075];

  /// Detalles vivos, de lejos a cerca. Reusan [SideProp] (misma proyección y
  /// mismo hueco mínimo con el asfalto) pero no se exponen como `props`.
  final List<SideProp> _bits = [];

  List<SideProp> _seedBits() {
    final list = <SideProp>[];
    for (final side in const [-1, 1]) {
      for (var i = 0; i < _bitCount; i++) {
        final k = i + (side > 0 ? 0.5 : 0.0) + 0.3;
        final kind = (i * 3 + (side > 0 ? 1 : 0)) % _bitKinds;
        list.add(
          SideProp(
            side: side,
            z: _propZMin + k * (_propSpan / _bitCount),
            widthFrac: _bitWidthFrac[kind],
            heightFrac: _bitHeightFrac[kind],
            lateralFrac: _bitLateral[(i + (side > 0 ? 4 : 0)) % _bitCount],
            // `style % _bitKinds` es el tipo de detalle.
            style: i * _bitKinds + kind,
          ),
        );
      }
    }
    return list;
  }

  void _sortBitsFarToNear() {
    _bits.sort((a, b) => b.z.compareTo(a.z));
  }

  // --- Detalles del asfalto ----------------------------------------------------
  /// Cantidad de detalles sobre la ruta. Viven en coordenada de mundo (la misma
  /// z que los props) y se reciclan sin asignar memoria.
  static const int _decalCount = 12;
  static const double _decalZMin = 1.0;
  static const double _decalSpan = 3.0;

  /// Carriles posibles (unidades de carril; el asfalto llega hasta ±1.14).
  static const List<double> _decalLanes = [
    -0.8, 0.3, 0.9, -0.2, 0.6, -1.0, 0.0, 0.95, -0.55,
  ];

  /// Tipos de detalle: 0 grieta, 1 mancha de aceite, 2 frenada, 3 arena que
  /// invade la ruta (siempre en el borde) y 4 parche de reparación. Cada
  /// bioma reparte su propia mezcla.
  static const List<List<int>> _decalKindsByBiome = [
    [3, 0, 1, 3, 4, 2, 3, 0], // desierto: mucha arena
    [0, 4, 0, 1, 2, 0, 4, 1], // ruinas: grietas y parches
    [3, 3, 0, 3, 2, 3, 1, 0], // cañón: arena y polvo
  ];

  /// Apaga el dibujo de los detalles del asfalto (solo para tests de look).
  @visibleForTesting
  bool drawDecals = true;

  final List<_Decal> _decals = [];
  int _decalSerial = 0;

  @visibleForTesting
  int get decalCount => _decals.length;

  /// Profundidad y carril de cada detalle (para los tests).
  @visibleForTesting
  List<({double z, double lane})> get decalSpots =>
      [for (final d in _decals) (z: d.z, lane: d.lane)];

  List<_Decal> _seedDecals() {
    final list = <_Decal>[];
    for (var i = 0; i < _decalCount; i++) {
      final decal = _Decal(z: _decalZMin + (i + 0.5) * (_decalSpan / _decalCount));
      _decalLook(decal, Biome.desert, i);
      list.add(decal);
    }
    return list;
  }

  /// Un detalle que dio la vuelta nace con la mezcla del bioma que viene.
  void _recycleDecal(_Decal decal) {
    _decalLook(decal, _spawnBiome, _decalCount + _decalSerial);
    _decalSerial++;
  }

  void _decalLook(_Decal decal, Biome biome, int serial) {
    final kinds = _decalKindsByBiome[biome.index];
    decal.kind = kinds[serial % kinds.length];
    decal.lane = decal.kind == 3
        ? (serial.isEven ? -1.06 : 1.06) // la arena entra desde el borde
        : _decalLanes[(serial * 5) % _decalLanes.length];
    decal.size = switch (decal.kind) {
      0 => 0.34,
      1 => 0.30,
      2 => 0.36,
      3 => 0.42,
      _ => 0.40,
    };
    decal.seed = serial * 7919 + 13;
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
  static const double _dashZMax = 14.0;

  /// Los divisores se desvanecen entre estas profundidades: nacen suaves cerca
  /// del horizonte en vez de aparecer de golpe (y sin parpadeo sub-píxel).
  static const double _dashFadeStart = 4.0;
  static const double _dashFadeEnd = 13.0;

  /// Líneas de borde: llegan casi hasta el punto de fuga, en tramos largos de
  /// pintura gastada.
  static const double _edgePeriod = 3.0;
  static const double _edgeZMax = 40.0;

  /// Avance del patrón en z (misma unidad que las rayas y los props).
  double _dashPhase = 0;

  /// Avance total en z: da identidad estable a cada tramo de pintura (el
  /// desgaste de cada uno no cambia mientras se acerca).
  double _dashTravel = 0;

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
    _distance += max(0.0, worldSpeed) * dt;
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
      if (z > prop.z) {
        reordered = true; // dio la vuelta: va al fondo
        _recycleLook(prop); // y nace con el aspecto del bioma que viene
      }
      prop.z = z;
    }
    if (reordered) _sortPropsFarToNear();

    // Los detalles de suelo corren igual que los props.
    var bitsReordered = false;
    for (final bit in _bits) {
      var z = bit.z - dz;
      while (z < _propZMin) {
        z += _propSpan;
      }
      if (z > bit.z) bitsReordered = true;
      bit.z = z;
    }
    if (bitsReordered) _sortBitsFarToNear();

    // Detalles del asfalto (grietas, manchas...): mismo avance y reciclado.
    for (final decal in _decals) {
      var z = decal.z - dz;
      var wrapped = false;
      while (z < _decalZMin) {
        z += _decalSpan;
        wrapped = true;
      }
      decal.z = z;
      if (wrapped) _recycleDecal(decal);
    }

    // El punteado de las divisorias corre en z con la misma velocidad.
    _dashPhase = _wrap(_dashPhase - dz, _dashPeriod);
    _dashTravel += dz;
  }

  /// Paleta vigente: la del tema (fundida día/noche según [blend]), tintada
  /// por la mezcla de biomas. En pleno desierto devuelve la paleta base tal
  /// cual.
  _Palette _paletteFor(double blend) {
    final base = _Palette.lerp(_light, _dark, blend);
    final b = biomeAt(_distance);
    if (b.from == Biome.desert && b.mix == 0) return base;
    final a = _biomeColors(b.from, base);
    final z = _biomeColors(b.to, base);
    return base.withBiome(
      skyBottom: _mix(a.skyBottom, z.skyBottom, b.mix),
      sandFar: _mix(a.sandFar, z.sandFar, b.mix),
      sandNear: _mix(a.sandNear, z.sandNear, b.mix),
      ridgeFar: _mix(a.ridgeFar, z.ridgeFar, b.mix),
      ridgeLit: _mix(a.ridgeLit, z.ridgeLit, b.mix),
      duneNear: _mix(a.duneNear, z.duneNear, b.mix),
      shoulder: _mix(a.shoulder, z.shoulder, b.mix),
      haze: _mix(a.haze, z.haze, b.mix),
      pyrLit: _mix(a.pyrLit, z.pyrLit, b.mix),
      pyrShade: _mix(a.pyrShade, z.pyrShade, b.mix),
    );
  }

  static Color _mix(Color x, Color y, double t) => Color.lerp(x, y, t)!;

  /// Colores de [biome] con el fundido día/noche de [base] (`base.night`).
  _BiomeColors _biomeColors(Biome biome, _Palette base) {
    switch (biome) {
      case Biome.desert:
        return (
          skyBottom: base.skyBottom,
          sandFar: base.sandFar,
          sandNear: base.sandNear,
          ridgeFar: base.ridgeFar,
          ridgeLit: base.ridgeLit,
          duneNear: base.duneNear,
          shoulder: base.shoulder,
          haze: base.haze,
          pyrLit: base.pyrLit,
          pyrShade: base.pyrShade,
        );
      case Biome.ruins:
        return _lerpBiome(_ruinsDay, _ruinsNight, base.night);
      case Biome.canyon:
        return _lerpBiome(_canyonDay, _canyonNight, base.night);
    }
  }

  static _BiomeColors _lerpBiome(_BiomeColors d, _BiomeColors n, double t) => (
        skyBottom: _mix(d.skyBottom, n.skyBottom, t),
        sandFar: _mix(d.sandFar, n.sandFar, t),
        sandNear: _mix(d.sandNear, n.sandNear, t),
        ridgeFar: _mix(d.ridgeFar, n.ridgeFar, t),
        ridgeLit: _mix(d.ridgeLit, n.ridgeLit, t),
        duneNear: _mix(d.duneNear, n.duneNear, t),
        shoulder: _mix(d.shoulder, n.shoulder, t),
        haze: _mix(d.haze, n.haze, t),
        pyrLit: _mix(d.pyrLit, n.pyrLit, t),
        pyrShade: _mix(d.pyrShade, n.pyrShade, t),
      );

  /// Mantiene [value] en [0, mod) (módulo siempre positivo).
  static double _wrap(double value, double mod) => ((value % mod) + mod) % mod;

  /// Dibuja el desierto completo.
  ///
  /// [blend] mezcla las dos paletas: 0 = día (tema claro), 1 = noche
  /// estrellada (tema oscuro). El fundido lo maneja el juego
  /// (`RunnerGame.themeBlend`), que lo anima al alternar el tema.
  void render(
    Canvas canvas,
    Perspective p, {
    required double blend,
    required double playerX,
  }) {
    if (p.width <= 0 || p.height <= 0) return;
    final c = _paletteFor(blend);
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

    // 2) Estrellas (aparecen con la noche, atenuadas durante el fundido) -----
    if (c.night > 0) {
      for (var i = 0; i < _stars.length; i++) {
        final star = _stars[i];
        final tw = 0.4 + 0.4 * sin(_time * 2.2 + star.dx * 47);
        final pos = Offset(star.dx * w, star.dy * vy);
        canvas.drawCircle(
          pos,
          1.0 + star.dy * 0.6,
          Paint()..color = c.star.withValues(alpha: tw * c.night),
        );
        // Una de cada nueve brilla con destello en cruz.
        if (i % 9 == 0) {
          final spark = Paint()
            ..color = c.star.withValues(alpha: tw * c.night)
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round;
          final len = 3.5 + 2.5 * tw;
          canvas.drawLine(pos.translate(-len, 0), pos.translate(len, 0), spark);
          canvas.drawLine(pos.translate(0, -len), pos.translate(0, len), spark);
        }
      }
      if (c.night >= 1) _drawShootingStar(canvas, w: w, vy: vy);
    }

    // 3) Luna o sol, con su halo ------------------------------------------------
    _drawCelestialBody(canvas, w: w, vy: vy, c: c);

    // 4) Nubes de ceniza, humo lejano y cuervos -------------------------------------------------
    _drawClouds(canvas, w: w, baseY: vy, c: c, sway: sway);
    _drawHorizonFire(canvas, w: w, vy: vy, c: c);
    _drawSmokeColumns(canvas, w: w, vy: vy, c: c);
    if (c.night < 1) {
      // De día vuelan; durante el fundido se desvanecen con la luz.
      _drawBirds(canvas, w: w, vy: vy, sway: sway, amount: 1 - c.night);
    }

    // 5) Capas de parallax: pirámides, mesetas, dunas medias y cercanas --------
    _drawPyramids(
      canvas,
      w: w,
      baseY: vy,
      offset: _time * 2 + sway * 0.03,
      c: c,
    );
    _drawMesas(
      canvas,
      w: w,
      baseY: vy,
      period: 132,
      offset: _time * 4 + sway * 0.05,
      heights: _mesas,
      maxHeight: vy * 0.62,
      paint: Paint()..color = Color.lerp(c.ridgeFar, c.haze, 0.40)!,
      rim: Paint()
        ..color = Color.lerp(c.ridgeLit, c.haze, 0.40)!.withValues(alpha: 0.75)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    if (drawSkyline) {
      _drawSkyline(
        canvas,
        w: w,
        baseY: vy,
        offset: _time * 5 + sway * 0.055 + 90,
        c: c,
      );
    }
    _drawBumps(
      canvas,
      w: w,
      baseY: vy,
      period: 210,
      offset: _time * 6 + sway * 0.06 + 40,
      heights: const [0.5, 0.9, 0.6, 1.0, 0.4],
      maxHeight: vy * 0.24,
      paint: Paint()
        ..color = Color.lerp(
            Color.lerp(c.ridgeFar, c.duneNear, 0.55)!, c.haze, 0.22)!,
    );
    _drawBumps(
      canvas,
      w: w,
      baseY: vy,
      period: 168,
      offset: _time * 9 + sway * 0.08,
      heights: _dunes,
      maxHeight: vy * 0.34,
      paint: Paint()..color = Color.lerp(c.duneNear, c.haze, 0.06)!,
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

    // Rachas de viento sobre la arena (van por debajo de la ruta).
    _drawWindStreaks(canvas, p, c);

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

    // Cordones gastados (óxido y concreto sucio) sobre el hombro.
    _drawKerbs(canvas, p, c);

    // 8) Marcas viales (recortadas al asfalto) -----------------------------------
    canvas.save();
    canvas.clipPath(roadPath);

    // Detalles del asfalto (grietas, aceite, frenadas, arena, parches).
    if (drawDecals) _drawRoadDecals(canvas, p, c);

    // Huellas gastadas de neumáticos: dan profundidad y guían el carril.
    if (drawDecals) _drawTireWear(canvas, p);

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
    _drawEdgeLines(canvas, p, c);
    canvas.restore();

    // Loma al final de la ruta: la carretera se pierde detrás de una lomada
    // baja en vez de terminar en punta contra una línea recta. El borde
    // inferior se desvanece para no dejar costura sobre la arena.
    final hillTop = vy - vy * 0.10;
    final hillBase = vy + p.corridorHeight * 0.045;
    final hillHalf = w * 0.24;
    final hillColor = Color.lerp(
        Color.lerp(c.sandFar, c.duneNear, 0.45)!, c.haze, 0.18)!;
    canvas.drawPath(
      Path()
        ..moveTo(vx - hillHalf, hillBase)
        ..quadraticBezierTo(vx, hillTop - (hillBase - hillTop), vx + hillHalf,
            hillBase)
        ..close(),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, hillTop),
          Offset(0, hillBase),
          [hillColor, hillColor, hillColor.withValues(alpha: 0.0)],
          [0.0, 0.6, 1.0],
        ),
    );

    // 9) Props de desierto (lejos primero: los cercanos pisan a los lejanos) ---
    _drawProps(canvas, p, c, sway: sway);

    // 10) Bruma del horizonte: una sola banda (antes eran cuatro franjas
    // translúcidas apiladas, que ensuciaban el borde). Es más densa justo en
    // el horizonte y se disuelve hacia el cielo y hacia la ruta; al morir
    // pronto no tapa diamantes ni obstáculos que recién aparecen.
    final hazeTop = vy - vy * 0.38;
    final hazeBottom = vy + p.corridorHeight * 0.12;
    final hazePeak = (vy - hazeTop) / (hazeBottom - hazeTop);
    canvas.drawRect(
      Rect.fromLTRB(0, hazeTop, w, hazeBottom),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, hazeTop),
          Offset(0, hazeBottom),
          [
            c.haze.withValues(alpha: 0.0),
            c.haze.withValues(alpha: 0.55),
            c.haze.withValues(alpha: 0.0),
          ],
          [0.0, hazePeak, 1.0],
        ),
    );
  }

  /// Resplandor de los incendios al pie de cada columna de humo: un óvalo
  /// naranja brasa (el acento de la marca) que parpadea y queda DETRÁS de las
  /// mesetas y de las dunas, así las siluetas se ven a contraluz. De día es
  /// apenas un tinte cálido; de noche es lo que más ilumina el horizonte.
  void _drawHorizonFire(
    Canvas canvas, {
    required double w,
    required double vy,
    required _Palette c,
  }) {
    final strength = 0.12 + 0.30 * c.night;
    for (final (fx, hf, phase) in const [
      (0.16, 0.78, 0.0),
      (0.58, 0.62, 1.7),
      (0.90, 0.70, 3.1),
    ]) {
      // Dos senos desfasados: parpadeo irregular, sin patrón evidente.
      final flicker =
          0.86 + 0.14 * sin(_time * 3.1 + phase * 2.3) * sin(_time * 1.7 + phase);
      final r = w * 0.17 * (0.8 + 0.4 * hf);
      canvas.save();
      canvas.translate(w * fx, vy);
      canvas.scale(1.0, 0.55); // óvalo chato: el fuego está lejos, en el piso
      canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            r,
            [
              AppColors.ember.withValues(alpha: strength * flicker),
              AppColors.ember.withValues(alpha: 0.0),
            ],
          ),
      );
      canvas.restore();
    }
  }

  /// Columnas de humo lejanas sobre el horizonte: ciudades que se queman.
  void _drawSmokeColumns(
    Canvas canvas, {
    required double w,
    required double vy,
    required _Palette c,
  }) {
    final smoke = Color.lerp(
      const Color(0xFF3A2A24),
      const Color(0xFF05060F),
      c.night,
    )!;
    for (final (fx, hf, phase) in const [
      (0.16, 0.78, 0.0),
      (0.58, 0.62, 1.7),
      (0.90, 0.70, 3.1),
    ]) {
      final baseX = w * fx;
      final height = vy * hf;
      const puffs = 9;
      for (var i = 0; i < puffs; i++) {
        final u = i / (puffs - 1); // 0 = base, 1 = punta de la columna
        final drift = sin(_time * 0.35 + phase + u * 2.4) * 10 * u + u * u * 26;
        final r = 6 + 20 * u;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(baseX + drift, vy - height * u),
            width: r * 2.2,
            height: r * 1.5,
          ),
          Paint()
            ..color = smoke.withValues(
              alpha: (0.34 * (1 - u * 0.75)).clamp(0.0, 1.0).toDouble(),
            ),
        );
      }
    }
  }

  /// Capa final de ambientación, sobre todo el mundo y bajo el HUD: un velo
  /// sucio que apaga los colores, viñeta oscura en los bordes y ceniza
  /// flotando. Es lo que baja el tono de "juego infantil" a "fin del mundo".
  /// [blend] va de 0 (tema claro) a 1 (tema oscuro), igual que en [render].
  void renderGrade(Canvas canvas, Perspective p, {required double blend}) {
    if (p.width <= 0 || p.height <= 0) return;
    final w = p.width;
    final h = p.height;
    final rect = Offset.zero & Size(w, h);

    canvas.drawRect(
      rect,
      Paint()
        ..color =
            const Color(0xFF2B1810).withValues(alpha: 0.20 - 0.10 * blend),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(w * 0.5, h * 0.55),
          max(w, h) * 0.75,
          [
            const Color(0x00000000),
            const Color(0xFF000000).withValues(alpha: 0.50 + 0.05 * blend),
          ],
          [0.55, 1.0],
        ),
    );

    // Ceniza que cae en diagonal (posiciones deterministas, sin Random).
    final ash = Paint()
      ..color = Color.lerp(
        const Color(0xFFD9CBB8),
        const Color(0xFFB8B0C8),
        blend,
      )!
          .withValues(alpha: 0.45);
    for (var i = 0; i < 26; i++) {
      final fx = _wrap(sin(i * 12.9898) * 43758.5453, 1.0);
      final fy = _wrap(sin(i * 78.233) * 24634.6345, 1.0);
      final x = _wrap(
        fx * w + sin(_time * 0.7 + i) * 14 - _time * (6 + i % 4),
        w,
      );
      final y = _wrap(fy * h + _time * (18 + (i % 5) * 7), h);
      canvas.drawCircle(Offset(x, y), 0.8 + (i % 3) * 0.5, ash);
    }

    // Brasas: chispas naranjas que suben despacio y se apagan (el acento de
    // la marca, también en el mapa). Pocas y chicas para no tapar el juego.
    final spark = Paint();
    for (var i = 0; i < 9; i++) {
      final fx = _wrap(sin(i * 91.345) * 15731.743, 1.0);
      final fy = _wrap(sin(i * 37.719) * 9631.129, 1.0);
      final speed = 0.035 + (i % 4) * 0.012; // fracción de pantalla por s
      final rise = _wrap(fy - _time * speed, 1.0); // 1 = abajo, 0 = arriba
      final x = fx * w + sin(_time * 1.3 + i * 2.1) * 12;
      final y = rise * h;
      final life = sin(rise * pi); // nace y muere suave en los extremos
      final glint = 0.6 + 0.4 * sin(_time * 7 + i * 1.9);
      final color = Color.lerp(AppColors.ember, AppColors.gold, (i % 3) / 2)!;
      spark.color = color.withValues(alpha: 0.22 * life * glint);
      canvas.drawCircle(Offset(x, y), 2.6, spark);
      spark.color = color.withValues(alpha: 0.85 * life * glint);
      canvas.drawCircle(Offset(x, y), 1.0, spark);
    }
  }

  // --- Primitivas de dibujo --------------------------------------------------

  void _drawCelestialBody(
    Canvas canvas, {
    required double w,
    required double vy,
    required _Palette c,
  }) {
    // Durante el fundido el cuerpo cruza el cielo: el sol se retira por la
    // derecha y la luna entra por la izquierda (nada de salto en seco).
    final night = c.night;
    final cx = w * (0.76 - 0.52 * night);
    final cy = vy * (0.54 - 0.10 * night);
    final r = 26.0 - 11.0 * night;
    // Halo: de noche tibio pero apagado, de día potente.
    canvas.drawCircle(
      Offset(cx, cy),
      r * 3.4,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(cx, cy),
          r * 3.4,
          [
            c.bodyGlow.withValues(alpha: 0.5 - 0.15 * night),
            c.bodyGlow.withValues(alpha: 0.0),
          ],
        ),
    );

    canvas.drawCircle(Offset(cx, cy), r, Paint()..color = c.body);

    // Dos cráteres para que se lea luna y no sol apagado: entran con la noche.
    if (night > 0) {
      final crater = Paint()..color = c.bodyShade.withValues(alpha: night);
      canvas.drawCircle(
        Offset(cx - r * 0.3, cy - r * 0.2),
        r * 0.22,
        crater,
      );
      canvas.drawCircle(
        Offset(cx + r * 0.28, cy + r * 0.3),
        r * 0.15,
        crater,
      );
    }
    // Sol sucio, velado por el humo: sin rayos ni cara. Se disipa al anochecer.
    if (night < 1) {
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()..color = c.haze.withValues(alpha: 0.28 * (1 - night)),
      );
    }
  }

  /// Estrella fugaz de noche: cruza el cielo cada ~7 s en menos de un segundo.
  void _drawShootingStar(Canvas canvas,
      {required double w, required double vy}) {
    const period = 7.0;
    const duration = 0.9;
    final local = _time % period;
    if (local > duration) return;
    final u = local / duration;
    final fade = sin(u * pi);
    final head = Offset(w * (0.88 - 0.42 * u), vy * (0.08 + 0.5 * u));
    final tail = Offset(head.dx + w * 0.16, head.dy - vy * 0.16);
    canvas.drawLine(
      tail,
      head,
      Paint()
        ..shader = ui.Gradient.linear(
          tail,
          head,
          [
            const Color(0x00FFFFFF),
            const Color(0xFFFFFFFF).withValues(alpha: 0.9 * fade),
          ],
        )
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      head,
      2.2,
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: fade),
    );
  }

  /// Bancos de ceniza: varios óvalos chatos en UN solo path (no se oscurecen
  /// donde se superponen, aunque el color sea translúcido) más una sombrita.
  void _drawClouds(
    Canvas canvas, {
    required double w,
    required double baseY,
    required _Palette c,
    required double sway,
  }) {
    final span = w + 240;
    final fill = Paint()..color = c.cloud;
    final shade = Paint()..color = c.cloudShade;
    for (final cloud in _clouds) {
      final raw = cloud.x0 + _time * cloud.speed + sway * 0.03;
      final x = ((raw % span) + span) % span - 120;
      final y = cloud.yFrac * baseY;
      final s = cloud.scale;
      // Bancos de ceniza: óvalos largos y chatos (nada de algodones).
      final path = Path()
        ..addOval(Rect.fromCenter(
            center: Offset(x, y), width: 96 * s, height: 13 * s))
        ..addOval(Rect.fromCenter(
            center: Offset(x - 30 * s, y + 4 * s),
            width: 58 * s,
            height: 10 * s))
        ..addOval(Rect.fromCenter(
            center: Offset(x + 34 * s, y + 3 * s),
            width: 62 * s,
            height: 11 * s))
        ..addOval(Rect.fromCenter(
            center: Offset(x + 6 * s, y - 5 * s),
            width: 44 * s,
            height: 10 * s));
      canvas.drawPath(path.shift(Offset(0, 2 * s)), shade);
      canvas.drawPath(path, fill);
    }
  }

  /// Tres cuervos aleteando a lo lejos (solo de día).
  void _drawBirds(
    Canvas canvas, {
    required double w,
    required double vy,
    required double sway,

    /// 1 = pleno día, 0 = noche: durante el fundido se desvanecen.
    required double amount,
  }) {
    final paint = Paint()
      ..color = const Color(0xFF14101A).withValues(alpha: 0.85 * amount)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final span = w + 160;
    for (final (x0, yf, speed, phase, s) in const [
      (0.0, 0.30, 30.0, 0.0, 1.0),
      (60.0, 0.36, 34.0, 1.3, 0.8),
      (30.0, 0.22, 28.0, 2.1, 0.9),
    ]) {
      final x = ((x0 + _time * speed + sway * 0.02) % span + span) % span - 80;
      final y = yf * vy + sin(_time * 1.6 + phase) * 3;
      final flap = sin(_time * 9 + phase) * 3.2 * s;
      final path = Path()
        ..moveTo(x - 7 * s, y - flap)
        ..quadraticBezierTo(x - 3.5 * s, y - 3 * s + flap * 0.3, x, y)
        ..quadraticBezierTo(
            x + 3.5 * s, y - 3 * s + flap * 0.3, x + 7 * s, y - flap);
      canvas.drawPath(path, paint);
    }
  }

  /// Pirámides lejanas en el horizonte: media cara iluminada, media en sombra.
  void _drawPyramids(
    Canvas canvas, {
    required double w,
    required double baseY,
    required double offset,
    required _Palette c,
    double fade = 0.55,
  }) {
    const period = 520.0;
    final first = (offset / period).floor() - 1;
    final slots = (w / period).ceil() + 3;
    // Perspectiva atmosférica: lo más lejano se funde con la bruma.
    final lit = Paint()..color = Color.lerp(c.pyrLit, c.haze, fade)!;
    final shade = Paint()..color = Color.lerp(c.pyrShade, c.haze, fade)!;
    for (var i = 0; i < slots; i++) {
      final x = (first + i) * period - offset;
      for (final (dx, half, hf) in const [
        (120.0, 46.0, 0.42),
        (196.0, 28.0, 0.24),
      ]) {
        final cx = x + dx;
        final top = baseY - baseY * hf;
        canvas.drawPath(
          Path()
            ..moveTo(cx - half, baseY)
            ..lineTo(cx, top)
            ..lineTo(cx, baseY)
            ..close(),
          lit,
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx, top)
            ..lineTo(cx + half, baseY)
            ..lineTo(cx, baseY)
            ..close(),
          shade,
        );
      }
    }
  }

  /// Rachas de viento: rayitas que cruzan la arena. Son decorado (se apagan
  /// con [drawProps]) y van por debajo del hombro y del asfalto, así que
  /// nunca se ven sobre la ruta.
  void _drawWindStreaks(Canvas canvas, Perspective p, _Palette c) {
    if (!drawProps) return;
    final span = p.width + 240;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (final (x0, f, speed) in const [
      (20.0, 0.18, 70.0),
      (210.0, 0.35, 95.0),
      (380.0, 0.55, 120.0),
      (120.0, 0.72, 150.0),
      (300.0, 0.90, 180.0),
    ]) {
      final y = p.vanishY + (p.height - p.vanishY) * f;
      final x = ((x0 + _time * speed) % span) - 120;
      final len = 30 + 70 * f;
      paint
        ..strokeWidth = 1 + 2 * f
        ..color = c.stripe.withValues(alpha: 0.30 - 0.14 * c.night);
      canvas.drawLine(Offset(x, y), Offset(x + len, y - len * 0.02), paint);
    }
  }

  /// Cordones rojo/blanco sobre el hombro de grava, pegados al asfalto. El
  /// patrón corre con la misma fase que las divisorias (período par), así que
  /// se mueve a la velocidad exacta del juego.
  void _drawKerbs(Canvas canvas, Perspective p, _Palette c) {
    const seg = _dashPeriod / 2;
    const zMax = 6.0;
    final laneIn = 1 + 2 * roadExtraFrac;
    final laneOut = laneIn + 2 * shoulderFrac * 0.55;
    final half = p.baseWidth * 0.5;
    final paint = Paint();
    for (final side in const [-1.0, 1.0]) {
      for (var k = -1;; k++) {
        final zNear = _dashZMin + _dashPhase + k * seg;
        if (zNear > zMax) break;
        final zFar = zNear + seg;
        if (zFar <= _dashZMin) continue;
        final tN = (1.0 / max(zNear, _dashZMin)).clamp(0.0, 1.0);
        final tF = (1.0 / min(zFar, zMax)).clamp(0.0, 1.0);
        final yN = p.yAtT(tN);
        final yF = p.yAtT(tF);
        paint.color = k.isEven ? c.kerbA : c.kerbB;
        canvas.drawPath(
          Path()
            ..moveTo(p.vanishX + side * half * laneIn * tN, yN)
            ..lineTo(p.vanishX + side * half * laneOut * tN, yN)
            ..lineTo(p.vanishX + side * half * laneOut * tF, yF)
            ..lineTo(p.vanishX + side * half * laneIn * tF, yF)
            ..close(),
          paint,
        );
      }
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

  // --- Siluetas de ciudad (parallax intermedio) ------------------------------

  /// Largo del patrón de edificios en px de pantalla (se repite en bucle).
  static const double _cityPeriod = 280;

  /// Peso de la ciudad por bioma: apenas insinuada en el desierto, plena en
  /// las ruinas y ausente en el cañón (ahí mandan las paredes de roca).
  static const List<double> _cityWeightByBiome = [0.30, 1.0, 0.0];

  /// Edificios de cada ranura del patrón: posición y ancho (fracción del
  /// período), alto (fracción del máximo) y remate (0 plano, 1 escalonado,
  /// 2 derrumbado en diagonal, 3 tanque de agua, 4 antena).
  static const List<({double x, double w, double h, int top})> _cityLots = [
    (x: 0.00, w: 0.17, h: 0.55, top: 0),
    (x: 0.17, w: 0.13, h: 0.85, top: 1),
    (x: 0.33, w: 0.20, h: 0.40, top: 3),
    (x: 0.55, w: 0.14, h: 1.00, top: 2),
    (x: 0.72, w: 0.12, h: 0.65, top: 4),
    (x: 0.86, w: 0.14, h: 0.45, top: 0),
  ];

  /// Apaga la capa de ciudad (solo para tests de look).
  @visibleForTesting
  bool drawSkyline = true;

  /// 0..1: cuánta ciudad se ve a esta distancia (mezcla suave entre biomas).
  @visibleForTesting
  static double cityWeight(double distance) {
    final b = biomeAt(distance);
    final a = _cityWeightByBiome[b.from.index];
    final z = _cityWeightByBiome[b.to.index];
    return a + (z - a) * b.mix;
  }

  /// Siluetas de edificios entre las mesetas y las dunas. Todos los edificios
  /// y todas las ventanas encendidas van en un solo `Path` cada uno (dos
  /// `drawPath` por frame). Nacen en el horizonte y nunca bajan de [baseY].
  void _drawSkyline(
    Canvas canvas, {
    required double w,
    required double baseY,
    required double offset,
    required _Palette c,
  }) {
    final weight = cityWeight(_distance);
    if (weight < 0.02 || baseY <= 0) return;

    final maxH = baseY * 0.40 * (0.55 + 0.45 * weight);
    final first = (offset / _cityPeriod).floor() - 1;
    final slots = (w / _cityPeriod).ceil() + 3;
    final body = Path();
    final lit = Path();

    for (var s = 0; s < slots; s++) {
      final k = first + s;
      final x0 = k * _cityPeriod - offset;
      for (var i = 0; i < _cityLots.length; i++) {
        // Un edificio de cada nueve falta (solar vacío, derrumbe).
        if ((k * 7 + i * 5) % 9 == 0) continue;
        final lot = _cityLots[i];
        final vary = 0.7 + 0.3 * (((k * 5 + i * 3) % 4 + 4) % 4) / 3;
        final bx = x0 + lot.x * _cityPeriod;
        final bw = lot.w * _cityPeriod;
        final hgt = lot.h * vary * maxH;
        if (bx + bw < 0 || bx > w) continue;

        switch (lot.top) {
          case 1: // escalonado
            body.addPolygon([
              Offset(bx, baseY),
              Offset(bx, baseY - hgt),
              Offset(bx + bw * 0.6, baseY - hgt),
              Offset(bx + bw * 0.6, baseY - hgt * 0.88),
              Offset(bx + bw, baseY - hgt * 0.88),
              Offset(bx + bw, baseY),
            ], true);
          case 2: // derrumbado en diagonal
            body.addPolygon([
              Offset(bx, baseY),
              Offset(bx, baseY - hgt),
              Offset(bx + bw * 0.55, baseY - hgt * 0.80),
              Offset(bx + bw, baseY - hgt * 0.72),
              Offset(bx + bw, baseY),
            ], true);
          default:
            body.addRect(Rect.fromLTRB(bx, baseY - hgt, bx + bw, baseY));
            if (lot.top == 3) {
              // Tanque de agua: patas finas y tambor.
              final tw = bw * 0.5;
              final tx = bx + bw * 0.25;
              body.addRect(Rect.fromLTRB(
                  tx, baseY - hgt - maxH * 0.10, tx + tw, baseY - hgt - maxH * 0.03));
              body.addRect(Rect.fromLTRB(tx + tw * 0.15, baseY - hgt - maxH * 0.03,
                  tx + tw * 0.25, baseY - hgt));
              body.addRect(Rect.fromLTRB(tx + tw * 0.75, baseY - hgt - maxH * 0.03,
                  tx + tw * 0.85, baseY - hgt));
            } else if (lot.top == 4) {
              final aw = max(1.5, bw * 0.05);
              final ax = bx + bw * 0.5 - aw * 0.5;
              body.addRect(
                  Rect.fromLTRB(ax, baseY - hgt - maxH * 0.22, ax + aw, baseY - hgt));
            }
        }

        // Ventanas encendidas (solo de noche): una de cada cuatro.
        if (c.night > 0) {
          final cols = (bw / 14).floor().clamp(1, 3);
          final rows = (hgt / 16).floor().clamp(0, 5);
          final gap = bw / (cols + 1);
          for (var r = 0; r < rows; r++) {
            for (var q = 0; q < cols; q++) {
              if ((k * 31 + i * 17 + r * 7 + q * 13) % 4 != 0) continue;
              final wx = bx + gap * (q + 1) - 1.5;
              final wy = baseY - hgt + 8 + r * 14.0;
              lit.addRect(Rect.fromLTWH(wx, wy, 3, 4));
            }
          }
        }
      }
    }

    final silhouette =
        Color.lerp(c.ridgeFar, c.skyBottom, 0.40 - 0.15 * c.night)!;
    canvas.drawPath(
      body,
      Paint()..color = silhouette.withValues(alpha: weight * (0.85 + 0.10 * c.night)),
    );
    if (c.night > 0) {
      canvas.drawPath(
        lit,
        Paint()
          ..color = const Color(0xFFE8B84A)
              .withValues(alpha: 0.8 * weight * c.night),
      );
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
    // `_props` y `_bits` vienen ordenados de lejos a cerca (mayor z primero):
    // se mezclan como en un merge para que un detalle cercano nunca quede
    // tapado por un prop lejano.
    var i = 0;
    var j = 0;
    while (i < _props.length || j < _bits.length) {
      final takeProp =
          j >= _bits.length || (i < _props.length && _props[i].z >= _bits[j].z);
      final item = takeProp ? _props[i++] : _bits[j++];
      final alpha = _propAlpha(item.z);
      if (alpha <= 0) continue;
      final body = item.rect(p, sway: sway);
      if (body.width < 1 || body.height < 1) continue;
      if (body.right < 0 || body.left > p.width) continue; // fuera de pantalla
      if (takeProp) {
        _drawProp(canvas, item, body, alpha, c);
      } else {
        _drawBit(canvas, item, body, alpha, c);
      }
    }
  }

  /// Los props lejanos se disuelven dentro de la bruma del horizonte.
  double _propAlpha(double z) =>
      ((_propFadeOutZ - z) / (_propFadeOutZ - _propFadeInZ)).clamp(0.0, 1.0);

  static Color _kindColor(int kind) => switch (kind) {
        0 => const Color(0xFF4F7A55), // cactus
        1 => const Color(0xFFB98A5E), // roca
        2 => const Color(0xFF9C8348), // arbusto seco
        3 => const Color(0xFFB0714B), // meseta
        5 => const Color(0xFF5B6168), // poste de luz
        6 => const Color(0xFF7A8A93), // auto abandonado
        7 => const Color(0xFF9AA0A6), // guardarraíl
        8 => const Color(0xFF8A8478), // edificio en ruinas
        9 => const Color(0xFF6E5B45), // alambrado
        10 => const Color(0xFFA8553A), // pilar de roca
        _ => const Color(0xFF9A9684), // cartel
      };

  void _drawProp(
    Canvas canvas,
    SideProp prop,
    Rect body,
    double alpha,
    _Palette c,
  ) {
    final kind = prop.style % _kindStride;

    // Tono propio de cada prop: dos vecinos no se funden en una hilera
    // indistinguible de siluetas del mismo color.
    final tone = ((prop.style * 37) % 21 - 10) / 100; // -0.10 .. +0.10
    var base = _kindColor(kind);
    // De noche todo cae hacia el tinte del desierto lunar; de día, color puro.
    if (c.night > 0) {
      base = Color.lerp(base, c.propNight, 0.45 * c.night)!;
    }
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
        _drawCactus(canvas, body, bodyPaint, alpha, c);
      case 1:
        _drawRock(canvas, body, bodyPaint, accent, alpha);
      case 2:
        _drawBush(canvas, body, bodyPaint, accent, alpha);
      case 3:
        _drawMesa(canvas, body, bodyPaint, accent, alpha);
      case 5:
        _drawLamp(canvas, prop, body, accent, alpha, c);
      case 6:
        _drawWreck(canvas, prop, body, bodyPaint, alpha);
      case 7:
        _drawGuardrail(canvas, prop, body, bodyPaint, accent, alpha);
      case 8:
        _drawRuin(canvas, prop, body, bodyPaint, accent, alpha, c);
      case 9:
        _drawFence(canvas, prop, body, accent, alpha);
      case 10:
        _drawSpire(canvas, body, bodyPaint, accent, alpha);
      default:
        _drawSign(canvas, body, bodyPaint, accent, alpha);
    }
  }

  /// Cactus saguaro reseco: tronco con brazos y una costilla clara. Toda la
  /// figura vive dentro del rectángulo, ya garantizado fuera de la ruta.
  void _drawCactus(
    Canvas canvas,
    Rect body,
    Paint paint,
    double alpha,
    _Palette c,
  ) {
    final cx = body.center.dx;
    final trunkW = max(3.0, body.width * 0.46);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx - trunkW * 0.5, body.top, trunkW, body.height),
        Radius.circular(trunkW * 0.5),
      ),
      paint,
    );

    if (body.height >= 24) {
      final armLen = min(body.width * 0.30, (body.width - trunkW) * 0.5);
      if (armLen >= 2) {
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
    }

    // Costilla clara a lo largo del tronco: da volumen.
    if (trunkW >= 6) {
      canvas.drawLine(
        Offset(cx - trunkW * 0.18, body.top + trunkW * 1.0),
        Offset(cx - trunkW * 0.18, body.bottom - trunkW * 0.2),
        Paint()
          ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.16 * alpha)
          ..strokeWidth = max(1.0, trunkW * 0.09)
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  /// Roca: polígono irregular apoyado en el suelo con una cara iluminada,
  /// una costilla clara y una grieta.
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

    // Cara iluminada (luz desde arriba a la izquierda).
    canvas.drawPath(
      Path()
        ..moveTo(l + wd * 0.08, t + ht * 0.45)
        ..lineTo(l + wd * 0.30, t + ht * 0.06)
        ..lineTo(l + wd * 0.60, t)
        ..lineTo(l + wd * 0.50, t + ht * 0.5)
        ..close(),
      Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.18 * alpha),
    );

    canvas.drawLine(
      Offset(l + wd * 0.30, t + ht * 0.06),
      Offset(l + wd * 0.60, t),
      accent
        ..color = accent.color.withValues(alpha: 0.45 * alpha)
        ..strokeWidth = max(1.0, wd * 0.05)
        ..strokeCap = StrokeCap.round,
    );

    // Grieta en zigzag.
    canvas.drawPath(
      Path()
        ..moveTo(l + wd * 0.64, t + ht * 0.30)
        ..lineTo(l + wd * 0.58, t + ht * 0.50)
        ..lineTo(l + wd * 0.66, t + ht * 0.62)
        ..lineTo(l + wd * 0.60, t + ht * 0.82),
      Paint()
        ..color = accent.color.withValues(alpha: 0.5 * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, wd * 0.025)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Arbusto seco: tres bolitas de follaje, unas varillas que asoman y
  /// frutitos rojos.
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

  /// Meseta: talud ancho, paredes cortadas y plancha plana con franjas de
  /// colores (estratos) y un borde superior iluminado.
  void _drawMesa(
    Canvas canvas,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
  ) {
    final w = body.width;
    final h = body.height;
    final path = Path()
      ..moveTo(body.left, body.bottom)
      ..lineTo(body.left + w * 0.20, body.top + h * 0.28)
      ..lineTo(body.left + w * 0.28, body.top)
      ..lineTo(body.right - w * 0.22, body.top)
      ..lineTo(body.right - w * 0.14, body.top + h * 0.34)
      ..lineTo(body.right, body.bottom)
      ..close();
    canvas.drawPath(path, paint);

    // Franjas claras y oscuras alternadas, recortadas a la silueta.
    canvas.save();
    canvas.clipPath(path);
    final light = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.14 * alpha);
    final dark = Paint()..color = accent.color.withValues(alpha: 0.30 * alpha);
    for (final (f0, f1, isLight) in const [
      (0.30, 0.40, true),
      (0.46, 0.58, false),
      (0.64, 0.72, true),
      (0.78, 0.90, false),
    ]) {
      canvas.drawRect(
        Rect.fromLTRB(
          body.left,
          body.top + h * f0,
          body.right,
          body.top + h * f1,
        ),
        isLight ? light : dark,
      );
    }
    canvas.restore();

    // Labio superior iluminado.
    canvas.drawLine(
      Offset(body.left + w * 0.28, body.top),
      Offset(body.right - w * 0.22, body.top),
      Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.35 * alpha)
        ..strokeWidth = max(1.0, w * 0.02)
        ..strokeCap = StrokeCap.round,
    );
  }

  /// Cartel de ruta: poste, panel con borde rojo y, cuando está cerca, una
  /// calavera en píxeles (aviso de zona infectada, en el estilo 8 bits de los
  /// zombies). Si está lejos, dos barras que simulan texto.
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
    final panel = RRect.fromRectAndRadius(
      Rect.fromLTWH(body.left, body.top, w, panelH),
      radius,
    );
    canvas.drawRRect(panel, paint);
    canvas.drawRRect(
      panel.deflate(max(1.0, w * 0.04)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, w * 0.035)
        ..color = const Color(0xFF8C3B2E).withValues(alpha: 0.9 * alpha),
    );

    final bar = accent..color = accent.color.withValues(alpha: alpha * 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          body.left + w * 0.16,
          body.top + panelH * 0.22,
          w * 0.68,
          panelH * 0.14,
        ),
        Radius.circular(panelH * 0.07),
      ),
      bar,
    );

    if (w >= 14) {
      // Calavera de 7x6 píxeles. Los ojos son huecos por los que se ve el
      // panel; va en UN solo path para que los bordes no se oscurezcan.
      const rows = ['0111110', '1111111', '1001001', '1111111', '0111110', '0101010'];
      final cell = max(1.0, min(w * 0.46 / 7, panelH * 0.42 / rows.length));
      final ox = cx - cell * 3.5;
      final oy = body.top + panelH * 0.44;
      final skull = Path();
      for (var r = 0; r < rows.length; r++) {
        for (var q = 0; q < 7; q++) {
          if (rows[r][q] != '1') continue;
          skull.addRect(Rect.fromLTWH(
              ox + q * cell, oy + r * cell, cell + 0.4, cell + 0.4));
        }
      }
      canvas.drawPath(
        skull,
        Paint()..color = const Color(0xFF2A2420).withValues(alpha: 0.9 * alpha),
      );
    } else {
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
  }

  // --- Props de ruinas y cañón ---------------------------------------------------

  /// Poste de luz: mástil fino, brazo hacia la ruta y farol. De noche, una de
  /// cada dos farolas sigue encendida y deja un halo cálido.
  void _drawLamp(
    Canvas canvas,
    SideProp prop,
    Rect body,
    Paint accent,
    double alpha,
    _Palette c,
  ) {
    final w = body.width;
    final dir = -prop.side.toDouble(); // el brazo apunta hacia la ruta
    final poleW = max(2.0, w * 0.22);
    final poleX = body.center.dx - dir * w * 0.3;
    final armY = body.top + w * 0.2;
    final metal = accent.color.withValues(alpha: alpha);

    canvas.drawRect(
      Rect.fromLTWH(poleX - poleW * 0.5, armY, poleW, body.bottom - armY),
      Paint()..color = metal,
    );
    final headCenter = Offset(poleX + dir * w * 0.6, armY - w * 0.04);
    canvas.drawLine(
      Offset(poleX, armY),
      headCenter,
      Paint()
        ..color = metal
        ..strokeWidth = max(1.5, poleW * 0.8)
        ..strokeCap = StrokeCap.round,
    );

    final lit = c.night > 0.5 && prop.style % 2 == 0;
    if (lit) {
      canvas.drawCircle(
        headCenter,
        w * 1.1,
        Paint()
          ..shader = ui.Gradient.radial(
            headCenter,
            w * 1.1,
            [
              const Color(0xFFFFE2A0).withValues(alpha: 0.55 * alpha),
              const Color(0x00FFE2A0),
            ],
          ),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: headCenter, width: w * 0.32, height: w * 0.16),
        Radius.circular(max(1.0, w * 0.05)),
      ),
      Paint()
        ..color = (lit ? const Color(0xFFFFE2A0) : const Color(0xFF3A3F45))
            .withValues(alpha: alpha),
    );
  }

  /// Auto abandonado visto de atrás, volcado un poco hacia afuera de la ruta:
  /// carrocería, luneta oscura, ruedas y luces rotas.
  void _drawWreck(
    Canvas canvas,
    SideProp prop,
    Rect body,
    Paint paint,
    double alpha,
  ) {
    final w = body.width;
    final h = body.height;
    final l = body.left;
    final t = body.top;
    final ink = const Color(0xFF1B1A17).withValues(alpha: alpha);

    canvas.save();
    // Gira alrededor del centro de la base, con la parte alta hacia afuera.
    canvas.translate(body.center.dx, body.bottom);
    canvas.rotate(prop.side * 0.07);
    canvas.translate(-body.center.dx, -body.bottom);

    final wheelW = w * 0.14;
    final wheelH = h * 0.24;
    for (final x in [l + w * 0.07, l + w * 0.79]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, body.bottom - wheelH, wheelW, wheelH),
          Radius.circular(wheelW * 0.3),
        ),
        Paint()..color = ink,
      );
    }
    final cabin = Path()
      ..moveTo(l + w * 0.18, t + h * 0.42)
      ..lineTo(l + w * 0.27, t + h * 0.04)
      ..lineTo(l + w * 0.73, t + h * 0.04)
      ..lineTo(l + w * 0.82, t + h * 0.42)
      ..close();
    final trunk = RRect.fromRectAndRadius(
      Rect.fromLTWH(l, t + h * 0.40, w, h * 0.46),
      Radius.circular(max(1.0, w * 0.04)),
    );
    canvas.drawPath(cabin, paint);
    canvas.drawRRect(trunk, paint);
    canvas.drawPath(
      Path()
        ..moveTo(l + w * 0.24, t + h * 0.38)
        ..lineTo(l + w * 0.31, t + h * 0.10)
        ..lineTo(l + w * 0.69, t + h * 0.10)
        ..lineTo(l + w * 0.76, t + h * 0.38)
        ..close(),
      Paint()..color = const Color(0xFF1B2A33).withValues(alpha: 0.9 * alpha),
    );
    final light = Paint()
      ..color = const Color(0xFF4A1512).withValues(alpha: alpha);
    canvas.drawRect(Rect.fromLTWH(l + w * 0.04, t + h * 0.50, w * 0.12, h * 0.10), light);
    canvas.drawRect(Rect.fromLTWH(l + w * 0.84, t + h * 0.50, w * 0.12, h * 0.10), light);
    canvas.drawRRect(
      trunk,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = ink.withValues(alpha: 0.5 * alpha),
    );
    canvas.restore();
  }

  /// Guardarraíl: postes y vigas onduladas. En una de cada tres falta el
  /// tramo del medio (choque viejo).
  void _drawGuardrail(
    Canvas canvas,
    SideProp prop,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
  ) {
    final w = body.width;
    final h = body.height;
    final post = accent.color.withValues(alpha: alpha);
    final postW = max(2.0, w * 0.035);
    for (var i = 0; i < 4; i++) {
      final x = body.left + w * (0.06 + i * 0.29);
      canvas.drawRect(
        Rect.fromLTWH(x - postW * 0.5, body.top + h * 0.25, postW, h * 0.75),
        Paint()..color = post,
      );
    }
    final broken = prop.style % 3 == 0;
    for (var seg = 0; seg < 3; seg++) {
      if (broken && seg == 1) continue;
      final x0 = body.left + w * (0.06 + seg * 0.29);
      final x1 = x0 + w * 0.29;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x0, body.top + h * 0.12, x1, body.top + h * 0.48),
          Radius.circular(h * 0.08),
        ),
        paint,
      );
      canvas.drawLine(
        Offset(x0, body.top + h * 0.30),
        Offset(x1, body.top + h * 0.30),
        Paint()
          ..color = post.withValues(alpha: 0.5 * alpha)
          ..strokeWidth = max(0.8, h * 0.04),
      );
    }
  }

  /// Edificio en ruinas: silueta rota arriba, ventanas negras (algunas
  /// tapiadas; de noche, alguna con luz), mugre abajo y hierros retorcidos.
  void _drawRuin(
    Canvas canvas,
    SideProp prop,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
    _Palette c,
  ) {
    final w = body.width;
    final h = body.height;
    final l = body.left;
    final t = body.top;
    final ink = const Color(0xFF14161C);
    final shell = Path()
      ..moveTo(l, body.bottom)
      ..lineTo(l, t + h * 0.14)
      ..lineTo(l + w * 0.28, t)
      ..lineTo(l + w * 0.46, t + h * 0.09)
      ..lineTo(l + w * 0.70, t + h * 0.02)
      ..lineTo(body.right, t + h * 0.22)
      ..lineTo(body.right, body.bottom)
      ..close();
    canvas.drawPath(shell, paint);

    canvas.save();
    canvas.clipPath(shell);
    final windowW = w * 0.16;
    final windowH = h * 0.075;
    for (var row = 0; row < 6; row++) {
      for (var col = 0; col < 3; col++) {
        final k = prop.style + row * 3 + col;
        if (k % 5 == 0) continue; // ventana tapiada
        final lit = c.night > 0.5 && k % 7 == 0;
        canvas.drawRect(
          Rect.fromLTWH(
            l + w * (0.14 + col * 0.28),
            t + h * (0.24 + row * 0.115),
            windowW,
            windowH,
          ),
          Paint()
            ..color = (lit ? const Color(0xFFE8B84A) : ink)
                .withValues(alpha: (lit ? 0.85 : 0.75) * alpha),
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(l, t + h * 0.80, w, h * 0.20),
      Paint()..color = ink.withValues(alpha: 0.25 * alpha),
    );
    canvas.restore();

    canvas.drawPath(
      shell,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, w * 0.012)
        ..color = ink.withValues(alpha: 0.6 * alpha),
    );
    final rebar = Paint()
      ..strokeWidth = max(0.8, w * 0.012)
      ..strokeCap = StrokeCap.round
      ..color = accent.color.withValues(alpha: alpha);
    canvas.drawLine(Offset(l + w * 0.30, t + h * 0.01), Offset(l + w * 0.34, t - h * 0.04), rebar);
    canvas.drawLine(Offset(l + w * 0.62, t + h * 0.03), Offset(l + w * 0.58, t - h * 0.03), rebar);
  }

  /// Alambrado: postes torcidos con alambre flojo; en algunos falta un tramo.
  void _drawFence(
    Canvas canvas,
    SideProp prop,
    Rect body,
    Paint accent,
    double alpha,
  ) {
    final w = body.width;
    final h = body.height;
    final postPaint = Paint()
      ..color = accent.color.withValues(alpha: alpha)
      ..strokeWidth = max(1.5, w * 0.04)
      ..strokeCap = StrokeCap.round;
    final xs = [for (var i = 0; i < 4; i++) body.left + w * (0.05 + i * 0.30)];
    for (var i = 0; i < xs.length; i++) {
      final lean = (i + prop.style) % 3 == 0 ? w * 0.03 : 0.0;
      canvas.drawLine(
        Offset(xs[i], body.bottom),
        Offset(xs[i] + lean, body.top + h * (i.isOdd ? 0.12 : 0.0)),
        postPaint,
      );
    }
    final wire = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.7, w * 0.012)
      ..color = const Color(0xFF2A2724).withValues(alpha: 0.85 * alpha);
    for (var i = 0; i < xs.length - 1; i++) {
      if (prop.style % 4 == 1 && i == 2) continue; // tramo cortado
      for (final f in const [0.20, 0.55, 0.85]) {
        final y = body.top + h * f;
        canvas.drawPath(
          Path()
            ..moveTo(xs[i], y)
            ..quadraticBezierTo((xs[i] + xs[i + 1]) * 0.5, y + h * 0.08, xs[i + 1], y),
          wire,
        );
      }
    }
  }

  /// Pilar de roca del cañón: columna estratificada con una cara en sombra.
  void _drawSpire(
    Canvas canvas,
    Rect body,
    Paint paint,
    Paint accent,
    double alpha,
  ) {
    final w = body.width;
    final h = body.height;
    final l = body.left;
    final t = body.top;
    final path = Path()
      ..moveTo(l + w * 0.08, body.bottom)
      ..lineTo(l + w * 0.20, t + h * 0.55)
      ..lineTo(l + w * 0.10, t + h * 0.34)
      ..lineTo(l + w * 0.30, t + h * 0.12)
      ..lineTo(l + w * 0.50, t)
      ..lineTo(l + w * 0.70, t + h * 0.10)
      ..lineTo(l + w * 0.90, t + h * 0.38)
      ..lineTo(l + w * 0.80, t + h * 0.60)
      ..lineTo(l + w * 0.94, body.bottom)
      ..close();
    canvas.drawPath(path, paint);

    canvas.save();
    canvas.clipPath(path);
    final strata = Paint()
      ..color = accent.color.withValues(alpha: 0.35 * alpha)
      ..strokeWidth = max(1.0, w * 0.02);
    for (var i = 1; i < 7; i++) {
      final y = t + h * (i * 0.14);
      final dy = i.isEven ? h * 0.01 : -h * 0.01;
      canvas.drawLine(Offset(l, y + dy), Offset(l + w, y), strata);
    }
    canvas.drawRect(
      Rect.fromLTRB(l + w * 0.55, t, l + w, body.bottom),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.18 * alpha),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, w * 0.015)
        ..color = accent.color.withValues(alpha: 0.8 * alpha),
    );
  }

  /// Detalles de suelo: pasto seco, piedritas, huesos y cactus bebé.
  void _drawBit(
    Canvas canvas,
    SideProp bit,
    Rect body,
    double alpha,
    _Palette c,
  ) {
    final kind = bit.style % _bitKinds;
    Color tint(Color base) =>
        c.night > 0 ? Color.lerp(base, c.propNight, 0.45 * c.night)! : base;
    final w = body.width;
    final cx = body.center.dx;
    final bottom = body.bottom;

    // Sombrita de apoyo.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, bottom),
        width: w * 0.9,
        height: max(2.0, w * 0.2),
      ),
      Paint()..color = const Color(0xFF000000).withValues(alpha: 0.16 * alpha),
    );

    switch (kind) {
      case 0: // mata de pasto seco
        final blade = Paint()
          ..color = tint(const Color(0xFF8A8A4A)).withValues(alpha: alpha)
          ..strokeWidth = max(1.0, w * 0.09)
          ..strokeCap = StrokeCap.round;
        for (final (dx, lean, hf) in const [
          (-0.30, -0.22, 0.70),
          (-0.15, -0.08, 1.00),
          (0.00, 0.00, 0.85),
          (0.15, 0.10, 1.00),
          (0.30, 0.24, 0.70),
        ]) {
          canvas.drawLine(
            Offset(cx + dx * w, bottom),
            Offset(cx + (dx + lean) * w, bottom - body.height * hf),
            blade,
          );
        }
      case 1: // piedritas
        for (final (dx, rf, tone) in const [
          (-0.25, 0.20, 0.0),
          (0.12, 0.26, 0.12),
          (0.34, 0.14, -0.10),
        ]) {
          final r = w * rf;
          final base = tint(const Color(0xFFB59B7C));
          final lift =
              tone >= 0 ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx + dx * w, bottom - r * 0.55),
              width: r * 2,
              height: r * 1.3,
            ),
            Paint()
              ..color =
                  Color.lerp(base, lift, tone.abs())!.withValues(alpha: alpha),
          );
        }
      case 2: // huesos viejos
        final bone = Paint()
          ..color = tint(const Color(0xFFD9D2BF)).withValues(alpha: alpha)
          ..strokeWidth = max(1.2, w * 0.12)
          ..strokeCap = StrokeCap.round;
        final boneY = bottom - body.height * 0.18;
        canvas.drawLine(
          Offset(cx - w * 0.38, boneY),
          Offset(cx + w * 0.34, boneY - body.height * 0.12),
          bone,
        );
        canvas.drawLine(
          Offset(cx - w * 0.30, boneY - body.height * 0.22),
          Offset(cx + w * 0.36, boneY + body.height * 0.02),
          bone,
        );
        final skullC = Offset(cx + w * 0.02, boneY - body.height * 0.40);
        canvas.drawOval(
          Rect.fromCenter(center: skullC, width: w * 0.38, height: w * 0.32),
          Paint()
            ..color = tint(const Color(0xFFE4DECB)).withValues(alpha: alpha),
        );
        final socket = Paint()
          ..color = const Color(0xFF1B1A17).withValues(alpha: alpha);
        canvas.drawCircle(
            skullC.translate(-w * 0.07, 0), max(0.8, w * 0.05), socket);
        canvas.drawCircle(
            skullC.translate(w * 0.07, 0), max(0.8, w * 0.05), socket);
      default: // cactus bebé
        final capW = w * 0.45;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              cx - capW * 0.5,
              bottom - body.height * 0.8,
              capW,
              body.height * 0.8,
            ),
            Radius.circular(capW * 0.5),
          ),
          Paint()
            ..color = tint(const Color(0xFF4E8C5A)).withValues(alpha: alpha),
        );
    }
  }

  // --- Detalles del asfalto ---------------------------------------------------

  /// Grietas, manchas de aceite, frenadas, arena y parches sobre el asfalto.
  /// Se proyectan como cualquier objeto del mundo (`t = 1/z`) y van recortados
  /// a la ruta (se llama dentro del clip del asfalto, antes de las marcas
  /// viales, así las divisorias quedan encima).
  void _drawRoadDecals(Canvas canvas, Perspective p, _Palette c) {
    final half = p.baseWidth * 0.5;
    const ink = Color(0xFF05060A);
    for (final d in _decals) {
      final alpha = _propAlpha(d.z);
      if (alpha <= 0) continue;
      final t = (1.0 / d.z).clamp(0.0, 1.0);
      final cx = p.vanishX + d.lane * half * t;
      final cy = p.yAtT(t);
      final w = d.size * half * t;
      final h = w * 0.32; // la ruta se ve de costado: todo se achata
      if (w < 2) continue;

      switch (d.kind) {
        case 0: // grieta
          final r = Random(d.seed);
          final path = Path()..moveTo(cx - w * 0.5, cy);
          var x = cx - w * 0.5;
          for (var i = 0; i < 5; i++) {
            x += w * (0.16 + r.nextDouble() * 0.08);
            final y = cy - h * (0.2 + r.nextDouble() * 1.4) * (i.isEven ? 1.0 : 0.4);
            path.lineTo(x, y);
          }
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(0.8, w * 0.035)
              ..strokeJoin = StrokeJoin.round
              ..color = ink.withValues(alpha: 0.45 * alpha),
          );
        case 1: // mancha de aceite
          canvas.drawOval(
            Rect.fromCenter(center: Offset(cx, cy - h * 0.5), width: w, height: h),
            Paint()..color = ink.withValues(alpha: 0.30 * alpha),
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx - w * 0.1, cy - h * 0.55),
              width: w * 0.5,
              height: h * 0.45,
            ),
            Paint()..color = c.roadLine.withValues(alpha: 0.06 * alpha),
          );
        case 2: // frenada: dos huellas que se curvan
          final len = h * 3.2;
          for (final off in const [-0.18, 0.18]) {
            canvas.drawPath(
              Path()
                ..moveTo(cx + off * w, cy)
                ..quadraticBezierTo(
                  cx + (off + 0.15) * w,
                  cy - len * 0.5,
                  cx + (off + 0.05) * w,
                  cy - len,
                ),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeCap = StrokeCap.round
                ..strokeWidth = max(1.0, w * 0.07)
                ..color = ink.withValues(alpha: 0.32 * alpha),
            );
          }
        case 3: // arena que invade desde el borde
          final sand = Paint()..color = c.sandNear.withValues(alpha: 0.55 * alpha);
          canvas.drawOval(
            Rect.fromCenter(center: Offset(cx, cy - h * 0.5), width: w, height: h),
            sand,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx - w * 0.22, cy - h * 0.9),
              width: w * 0.55,
              height: h * 0.7,
            ),
            sand,
          );
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(cx + w * 0.2, cy - h * 0.2),
              width: w * 0.5,
              height: h * 0.5,
            ),
            sand,
          );
        default: // parche de reparación
          final patch = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(cx, cy - h * 0.5),
              width: w * 0.9,
              height: h * 0.9,
            ),
            Radius.circular(max(1.0, h * 0.12)),
          );
          canvas.drawRRect(
            patch,
            Paint()
              ..color = Color.lerp(c.roadNear, Colors.black, 0.2)!
                  .withValues(alpha: 0.45 * alpha),
          );
          canvas.drawRRect(
            patch,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = max(0.8, w * 0.015)
              ..color = c.roadLine.withValues(alpha: 0.10 * alpha),
          );
      }
    }
  }

  // --- Marcas viales ----------------------------------------------------------

  /// Dos huellas oscuras por carril (donde pasan las ruedas), en tramos con
  /// huecos y desgaste irregular. Corren en coordenada de mundo igual que los
  /// bordes y se desvanecen con la distancia. Van bajo las divisorias y no
  /// pisan el hombro: el recorte al asfalto lo hace quien llama.
  void _drawTireWear(Canvas canvas, Perspective p) {
    const ink = Color(0xFF05060A);
    const zMax = 24.0;
    final phase = _wrap(-_dashTravel, _edgePeriod);
    final id0 = (_dashTravel / _edgePeriod).ceil();
    var salt = 20;
    for (final center in const [-1.0, 0.0, 1.0]) {
      for (final off in const [-0.15, 0.15]) {
        salt++;
        final lane = center + off;
        // La huella externa del carril de la orilla cae fuera del asfalto.
        if (lane.abs() > 1.07) continue;
        for (var m = -1;; m++) {
          final zNear = _dashZMin + phase + m * _edgePeriod;
          if (zNear > zMax) break;
          final id = id0 + m;
          final w1 = _hash01(id, salt);
          final w2 = _hash01(id, salt + 40);
          final zA = max(zNear, _dashZMin);
          final zB = min(zNear + _edgePeriod * (0.55 + 0.40 * w1), zMax);
          if (zB <= zA) continue;
          final fade = _fadeOut((zA + zB) * 0.5, 5.0, zMax);
          if (fade <= 0.01) continue;
          _drawLaneSegment(
            canvas,
            p,
            lane,
            zNear: zA,
            zFar: zB,
            widthBase: 11.0,
            color: ink,
            alpha: (0.05 + 0.08 * w2) * fade,
          );
        }
      }
    }
  }

  /// Manchones de la divisoria `lane` (±0.5): la fase avanza con el juego en
  /// coordenada de mundo y cada manchón se afila con la perspectiva.
  void _drawLaneDashes(Canvas canvas, Perspective p, double lane, _Palette c) {
    // Amarillo de pintura vial; de noche se apaga hacia un tono arena.
    final paint = Color.lerp(
        const Color(0xFFE2B43C), const Color(0xFFC8B173), c.night)!;
    final salt = lane > 0 ? 1 : 2;
    final id0 = (_dashTravel / _dashPeriod).ceil();

    void seg(double a, double b, double alpha) {
      final zA = max(a, _dashZMin);
      final zB = min(b, _dashZMax);
      if (zB <= zA) return;
      final fade = _fadeOut((zA + zB) * 0.5, _dashFadeStart, _dashFadeEnd);
      if (fade <= 0.01) return;
      _drawLaneSegment(
        canvas,
        p,
        lane,
        zNear: zA,
        zFar: zB,
        widthBase: 5.5,
        color: paint,
        alpha: alpha * fade,
      );
    }

    for (var m = -1;; m++) {
      final zNear = _dashZMin + _dashPhase + m * _dashPeriod;
      if (zNear > _dashZMax) break;
      if (zNear + _dashLen <= _dashZMin) continue; // todavía no entró
      // Pintura gastada: cada manchón tiene su propio desgaste (estable).
      final id = id0 + m;
      final w1 = _hash01(id, salt);
      final w2 = _hash01(id, salt + 10);
      final w3 = _hash01(id, salt + 20);
      final alpha = 0.55 + 0.40 * w1; // unos más descoloridos que otros
      final len = _dashLen * (1.0 - 0.30 * w2); // algunos más cortos
      if (w3 > 0.72) {
        // Manchón con un bache de pintura saltada.
        final hole = len * (0.35 + 0.30 * w1);
        const hw = 0.035;
        seg(zNear, zNear + hole, alpha);
        seg(zNear + hole + hw, zNear + len, alpha * 0.85);
      } else {
        seg(zNear, zNear + len, alpha);
      }
    }
  }

  /// Bordes del asfalto: blanco sucio, en tramos largos con huecos y
  /// descoloridos irregulares. Se extienden hasta casi el punto de fuga y se
  /// desvanecen con la distancia, así la ruta converge de verdad en el
  /// horizonte en vez de cortarse antes.
  void _drawEdgeLines(Canvas canvas, Perspective p, _Palette c) {
    final paint = Color.lerp(c.roadLine, const Color(0xFF8F8A78), 0.32)!;
    final phase = _wrap(-_dashTravel, _edgePeriod);
    final id0 = (_dashTravel / _edgePeriod).ceil();
    final lane = 1 + 2 * roadExtraFrac;
    for (final side in const [-1.0, 1.0]) {
      final salt = side > 0 ? 3 : 4;
      for (var m = -1;; m++) {
        final zNear = _dashZMin + phase + m * _edgePeriod;
        if (zNear > _edgeZMax) break;
        final id = id0 + m;
        final w1 = _hash01(id, salt);
        final w2 = _hash01(id, salt + 10);
        // Lejos el hueco sería ruido sub-píxel: sólo se marca de cerca.
        final gap = zNear > 14.0
            ? 0.0
            : (w1 > 0.55 ? _edgePeriod * (0.06 + 0.22 * w1) : _edgePeriod * 0.03);
        final zA = max(zNear, _dashZMin);
        final zB = min(zNear + _edgePeriod - gap, _edgeZMax);
        if (zB <= zA) continue;
        final fade = _fadeOut((zA + zB) * 0.5, 6.0, _edgeZMax);
        _drawLaneSegment(
          canvas,
          p,
          side * lane,
          zNear: zA,
          zFar: zB,
          widthBase: 4.0,
          color: paint,
          alpha: (0.50 + 0.35 * w2) * fade,
        );
      }
    }
  }

  /// 1 → 0 entre [start] y [end] (suavizado).
  static double _fadeOut(double z, double start, double end) {
    final t = ((z - start) / (end - start)).clamp(0.0, 1.0).toDouble();
    return 1.0 - t * t * (3.0 - 2.0 * t);
  }

  /// Hash determinista en [0, 1): el desgaste de cada tramo de pintura se
  /// decide por su identidad y no cambia al acercarse.
  static double _hash01(int n, int salt) {
    final v = sin(n * 12.9898 + salt * 78.233) * 43758.5453;
    return v - v.floorToDouble();
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
  double widthFrac;

  /// Alto del prop sobre la altura de la pantalla (en la línea base).
  double heightFrac;

  /// Separación extra desde el hueco mínimo (0 = lo más cerca de la ruta).
  double lateralFrac;

  /// Semilla del aspecto: `style % MapRenderer._kindStride` elige el tipo de
  /// prop y el resto varía tono y detalles.
  ///
  /// El aspecto (ancho, alto, separación y estilo) no es final: cuando el prop
  /// da la vuelta y vuelve al fondo se le asigna un tipo del bioma vigente.
  int style;

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

/// Biomas del recorrido: rotan por distancia (ver [MapRenderer.biomeAt]).
enum Biome {
  /// Arena, cactus, mesetas y carteles de ruta.
  desert,

  /// Pueblo en ruinas: edificios rotos, postes, autos abandonados y barandas.
  ruins,

  /// Cañón rojo: pilares de roca, mesetas y polvo en la ruta.
  canyon,
}

/// Detalle pintado sobre el asfalto (grieta, aceite, frenada, arena, parche).
/// Mutable: al dar la vuelta se le asigna un aspecto del bioma que viene.
class _Decal {
  _Decal({required this.z});

  /// Profundidad en coordenada de mundo (1 = línea base).
  double z;

  /// Carril normalizado (±1 = bordes de la ruta de juego).
  double lane = 0;

  /// 0 grieta, 1 aceite, 2 frenada, 3 arena, 4 parche.
  int kind = 0;

  /// Ancho en unidades de carril.
  double size = 0.3;

  /// Semilla del trazo (grietas irregulares, siempre iguales para el mismo).
  int seed = 0;
}

/// Colores que cambian de un bioma a otro.
typedef _BiomeColors = ({
  Color skyBottom,
  Color sandFar,
  Color sandNear,
  Color ridgeFar,
  Color ridgeLit,
  Color duneNear,
  Color shoulder,
  Color haze,
  Color pyrLit,
  Color pyrShade,
});

// Ruinas: tierra gris, concreto y cielo polvoriento (haze = skyBottom, como en
// el desierto, para que la bruma se funda con el cielo).
const _BiomeColors _ruinsDay = (
  skyBottom: Color(0xFFD0A98A),
  sandFar: Color(0xFFA8A48C),
  sandNear: Color(0xFF7F7C68),
  ridgeFar: Color(0xFF6F7886),
  ridgeLit: Color(0xFFA3AAB5),
  duneNear: Color(0xFF8A8C7A),
  shoulder: Color(0xFF6E6C62),
  haze: Color(0xFFD0A98A),
  pyrLit: Color(0xFFA3AAB5),
  pyrShade: Color(0xFF6F7886),
);
const _BiomeColors _ruinsNight = (
  skyBottom: Color(0xFF34344E),
  sandFar: Color(0xFF3A3D4A),
  sandNear: Color(0xFF262833),
  ridgeFar: Color(0xFF1D2233),
  ridgeLit: Color(0xFF4A5470),
  duneNear: Color(0xFF30344A),
  shoulder: Color(0xFF1C1E2A),
  haze: Color(0xFF30344F),
  pyrLit: Color(0xFF4A5470),
  pyrShade: Color(0xFF1D2233),
);

// Cañón: roca roja y cielo anaranjado.
const _BiomeColors _canyonDay = (
  skyBottom: Color(0xFFEFA06A),
  sandFar: Color(0xFFD99062),
  sandNear: Color(0xFFB5623D),
  ridgeFar: Color(0xFF8C3F2A),
  ridgeLit: Color(0xFFD07F55),
  duneNear: Color(0xFFC4704A),
  shoulder: Color(0xFF8A4A33),
  haze: Color(0xFFEFA06A),
  pyrLit: Color(0xFFD07F55),
  pyrShade: Color(0xFF8C3F2A),
);
const _BiomeColors _canyonNight = (
  skyBottom: Color(0xFF45283F),
  sandFar: Color(0xFF4A2D3A),
  sandNear: Color(0xFF33202E),
  ridgeFar: Color(0xFF2B1730),
  ridgeLit: Color(0xFF6A3A55),
  duneNear: Color(0xFF40263A),
  shoulder: Color(0xFF27161F),
  haze: Color(0xFF40264D),
  pyrLit: Color(0xFF6A3A55),
  pyrShade: Color(0xFF2B1730),
);

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
    required this.cloudShade,
    required this.kerbA,
    required this.kerbB,
    required this.pyrLit,
    required this.pyrShade,
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

  /// Sombrita inferior de las nubes.
  final Color cloudShade;

  /// Cordones del hombro (franjas alternadas).
  final Color kerbA;
  final Color kerbB;

  /// Pirámides del horizonte: cara iluminada y cara en sombra.
  final Color pyrLit;
  final Color pyrShade;

  /// 0 = día (tema claro), 1 = noche estrellada (tema oscuro). Se interpola
  /// en [lerp] para fundir un tema con el otro.
  final double night;

  /// Mezcla paleta de día [a] con la de noche [b] según [t] (0..1).
  ///
  /// Es el fundido del cambio de tema: todo el color del desierto pasa de un
  /// modo al otro sin cortar en seco.
  static _Palette lerp(_Palette a, _Palette b, double t) {
    final k = t.clamp(0.0, 1.0).toDouble();
    Color mix(Color from, Color to) => Color.lerp(from, to, k)!;
    return _Palette(
      skyTop: mix(a.skyTop, b.skyTop),
      skyBottom: mix(a.skyBottom, b.skyBottom),
      star: mix(a.star, b.star),
      body: mix(a.body, b.body),
      bodyGlow: mix(a.bodyGlow, b.bodyGlow),
      bodyShade: mix(a.bodyShade, b.bodyShade),
      cloud: mix(a.cloud, b.cloud),
      ridgeFar: mix(a.ridgeFar, b.ridgeFar),
      ridgeLit: mix(a.ridgeLit, b.ridgeLit),
      duneNear: mix(a.duneNear, b.duneNear),
      sandFar: mix(a.sandFar, b.sandFar),
      sandNear: mix(a.sandNear, b.sandNear),
      shoulder: mix(a.shoulder, b.shoulder),
      roadFar: mix(a.roadFar, b.roadFar),
      roadNear: mix(a.roadNear, b.roadNear),
      roadLine: mix(a.roadLine, b.roadLine),
      stripe: mix(a.stripe, b.stripe),
      haze: mix(a.haze, b.haze),
      propNight: mix(a.propNight, b.propNight),
      cloudShade: mix(a.cloudShade, b.cloudShade),
      kerbA: mix(a.kerbA, b.kerbA),
      kerbB: mix(a.kerbB, b.kerbB),
      pyrLit: mix(a.pyrLit, b.pyrLit),
      pyrShade: mix(a.pyrShade, b.pyrShade),
      night: a.night + (b.night - a.night) * k,
    );
  }

  /// Copia de la paleta con los colores que cambian entre biomas.
  _Palette withBiome({
    required Color skyBottom,
    required Color sandFar,
    required Color sandNear,
    required Color ridgeFar,
    required Color ridgeLit,
    required Color duneNear,
    required Color shoulder,
    required Color haze,
    required Color pyrLit,
    required Color pyrShade,
  }) =>
      _Palette(
        skyTop: skyTop,
        skyBottom: skyBottom,
        star: star,
        body: body,
        bodyGlow: bodyGlow,
        bodyShade: bodyShade,
        cloud: cloud,
        ridgeFar: ridgeFar,
        ridgeLit: ridgeLit,
        duneNear: duneNear,
        sandFar: sandFar,
        sandNear: sandNear,
        shoulder: shoulder,
        roadFar: roadFar,
        roadNear: roadNear,
        roadLine: roadLine,
        stripe: stripe,
        haze: haze,
        propNight: propNight,
        cloudShade: cloudShade,
        kerbA: kerbA,
        kerbB: kerbB,
        pyrLit: pyrLit,
        pyrShade: pyrShade,
        night: night,
      );
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
  cloudShade: Color(0x00000000),
  kerbA: Color(0xFF5E1F28),
  kerbB: Color(0xFF7C8196),
  pyrLit: Color(0xFF3B3358),
  pyrShade: Color(0xFF2A2342),
  night: 1,
);

const _Palette _light = _Palette(
  skyTop: Color(0xFF3A6E9E),
  skyBottom: Color(0xFFE9B37C),
  star: Color(0xFFFFFFFF),
  body: Color(0xFFF6C556),
  bodyGlow: Color(0xFFFF9F4A),
  bodyShade: Color(0xFFFFE9B8),
  cloud: Color(0x99B9A894),
  ridgeFar: Color(0xFFB07A56),
  ridgeLit: Color(0xFFE8C08E),
  duneNear: Color(0xFFD9A55F),
  sandFar: Color(0xFFE6C688),
  sandNear: Color(0xFFC99650),
  shoulder: Color(0xFFA98858),
  roadFar: Color(0xFF8F949B),
  roadNear: Color(0xFF3E4249),
  roadLine: Color(0xFFE6DFC8),
  stripe: Color(0xFFFFFFFF),
  haze: Color(
      0xFFE9B37C), // = skyBottom: se funde con el cielo, sin banda lechosa
  propNight: Color(0xFF1A2233),
  cloudShade: Color(0x66584A44),
  kerbA: Color(0xFF7E2F2B),
  kerbB: Color(0xFFA9A293),
  pyrLit: Color(0xFFC99A62),
  pyrShade: Color(0xFF9E7143),
  night: 0,
);
