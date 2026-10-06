import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'perspective.dart';

/// Corredor con los tres gestos de Subway Surfers:
///
///  - **carril**: `lane` es el carril objetivo (-1, 0, 1) y `lanePos` la
///    posición interpolada; la X en pantalla sale de la perspectiva, así que
///    el cuerpo "se corre" por el corredor sin salirse de sus bordes,
///  - **salto**: parábola con gravedad (`jumpY` es la altura sobre el suelo),
///  - **agacharse**: `rollTimer` encendido, con la caja de colisión achicada.
///
/// La fila del suelo (`_groundY`) es fija: la profundidad del jugador nunca
/// cambia, solo salta. Eso mantiene estable el carril y da una referencia
/// exacta para las colisiones por altura.
class PlayerComponent extends PositionComponent {
  static const double playerSize = 34;
  static const String _characterSvgAsset =
      'assets/images/character/kenney_platformerCharacters/adventurer_vector.svg';

  /// Atlas del corredor (lo genera `tools/build_player_atlas.py` a partir de la
  /// hoja original): celdas de 192x192 en 8 columnas. Los pies de todas las
  /// poses apoyan en la misma fila, así que alcanza con anclar la celda.
  static const String _atlasAsset = 'assets/images/character/player_atlas.png';
  static const int _atlasCols = 8;
  static const double _cell = 192;

  /// Fila de los pies dentro de la celda y alto del personaje parado (en px de
  /// celda): fijan la escala de dibujo.
  static const double _cellFeetY = 186;
  static const double _cellStandHeight = 150;

  /// Alto en pantalla del personaje parado.
  static const double _standHeightPx = 54;
  static const double _drawScale = _standHeightPx / _cellStandHeight;

  // Índices de las poses dentro del atlas.
  static const int _runFrames = 8; // 0..7: ciclo de carrera
  static const int _jumpCrouch = 8;
  static const int _jumpRise = 9;
  static const int _jumpApex = 10;
  static const int _jumpFall = 11;
  static const int _landing = 12;
  static const int _slideIn = 13;
  static const int _slideA = 14;
  static const int _slideB = 15;
  static const int _slideOut = 16;

  /// Cuadros de carrera por segundo a velocidad base (sube con [runRate]).
  static const double _runFps = 13;

  /// Cuánto dura la pose de aterrizaje y el impulso previo al salto.
  static const double _landDuration = 0.11;
  static const double _takeoffDuration = 0.05;

  /// Velocidad vertical (px/s) a partir de la cual se considera que sube o cae;
  /// en medio queda la pose del punto más alto.
  static const double _apexBand = 150;

  /// Inclinación máxima (rad) al cambiar de carril.
  static const double _maxLean = 0.13;

  /// Alto del jugador agachado: tiene que quedar por debajo de la banda del
  /// túnel ([ObstacleComponent] usa una banda 24..130 sobre el suelo).
  static const double rollHeight = 16;

  // --- Tuneo -----------------------------------------------------------------
  /// Carriles que recorre por segundo. Más rápido para que el cambio se sienta
  /// más directo y menos "pesado" en un runner móvil.
  static const double laneSpeed = 9.0;

  /// Salto más reactivo y con mejor sensación de juego móvil.
  static const double jumpSpeed = 420;
  static const double gravity = 1450;

  /// Duración y velocidad extra del empujón lateral de un choque.
  static const double bounceDuration = 0.3;
  static const double bounceBoost = 2.4;

  /// Duración del agachado y caída rápida al agacharse en el aire.
  static const double rollDuration = 0.48;
  static const double diveSpeed = 980;

  PlayerComponent({
    required Vector2 startPosition,
    required this.perspective,
  })  : _groundY = startPosition.y,
        super(
          position: startPosition,
          size: Vector2.all(playerSize),
          anchor: Anchor.center,
        );

  /// Geometría de perspectiva vigente (la refresca el juego en cada resize).
  Perspective perspective;

  /// Carril objetivo: -1, 0 o 1.
  int lane = 0;

  /// Posición interpolada entre carriles (-1..1). Es la que se dibuja.
  double lanePos = 0;

  /// Altura sobre la ruta en px (0 = apoyado en el asfalto). Es absoluta: arriba
  /// de un camión vale lo que mide su techo.
  double jumpY = 0;

  double jumpV = 0;

  /// Altura de la superficie que lo sostiene, en px sobre la ruta: 0 en el
  /// asfalto, la del techo (o de la rampa) cuando corre sobre un camión.
  /// [RunnerGame] la fija cada cuadro. Con los pies en esa altura está
  /// apoyado; si la superficie sube (rampa) lo acompaña, y si desaparece
  /// (fin del techo) cae.
  double groundHeight = 0;

  /// Segundos que quedan de empujón lateral tras chocar con un camión: el
  /// cambio de carril va más rápido para sacarlo del medio.
  double bounceTimer = 0;

  /// Tiempo restante de agachado.
  double rollTimer = 0;

  bool _pendingRoll = false;
  double _poseTime = 0;

  /// Velocidad de la carrera respecto de la base (1 = 260 px/s de mundo). La
  /// fija el juego cada frame: el corredor mueve las piernas al ritmo del piso.
  double runRate = 1;

  double _runPhase = 0; // en cuadros del ciclo de carrera
  double _airTime = 0;
  double _landTimer = 0;
  double _lean = 0;

  double _groundY;

  /// Fila de suelo del jugador: la profundidad nunca cambia.
  double get groundY => _groundY;

  /// Y de los pies cuando está apoyado (referencia de colisión).
  double get groundFeetY => _groundY + playerSize * 0.5;

  bool get isAirborne => jumpY > groundHeight + 0.01 || jumpV != 0;
  bool get isRolling => rollTimer > 0;

  /// Alto real del cuerpo: 34 parado, [rollHeight] agachado.
  double get bodyHeight => isRolling ? rollHeight : playerSize;

  /// Color base del cuerpo.
  static const Color _bodyColor = Color(0xFF378ADD);

  /// Arte del personaje cargado desde assets: el atlas es el principal, con
  /// fallback al SVG y luego al dibujo geométrico si falla la carga.
  ui.Image? _atlas;
  bool _spriteArtLoaded = false;

  ui.Picture? _characterPicture;
  bool _characterArtLoaded = false;

  bool get hasCustomArt =>
      (_spriteArtLoaded && _atlas != null) ||
      (_characterArtLoaded && _characterPicture != null);

  /// Opacidad de dibujo (1 = sólido). RunnerGame la baja mientras dure la
  /// invulnerabilidad (escudo recién roto o golpe pagado con diamantes) para
  /// que el respiro se vea en el corredor.
  double blinkAlpha = 1;

  final Paint _paint = Paint();
  final Paint _stroke = Paint()
    ..strokeWidth = 3
    ..strokeCap = StrokeCap.round;

  @override
  Future<void> onLoad() async {
    // El arte NO bloquea el montaje: se arranca en background y mientras
    // llega (o si falla) el corredor se dibuja con el cuerpo geométrico.
    //
    // Esperarlo acá traba toda la cola de montaje de Flame: un hijo que sigue
    // cargando deja al padre bloqueado, así que nada de lo que venga después
    // (cámara, obstáculos, monedas, camiones, zombis) llega a montarse y el
    // juego queda corriendo con un árbol vacío. En los tests ese I/O además
    // nunca termina (fake-async), lo que congelaba los juegos de punta a punta.
    _artReady = _loadCharacterArt();
    unawaited(_artReady);
  }

  /// Última carga de arte arrancada (en curso o terminada). Permite que un
  /// test espere a que el sprite deje de ser el de reemplazo sin depender del
  /// detalle de implementación del `onLoad`.
  Future<void> get artReady => _artReady ?? Future<void>.value();

  Future<void>? _artReady;

  Future<void> _loadCharacterArt() async {
    try {
      final data = await rootBundle.load(_atlasAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _atlas = frame.image;
      _spriteArtLoaded = true;
      _characterArtLoaded = false;
      _characterPicture = null;
      return;
    } catch (error, stackTrace) {
      debugPrint('Failed to load player atlas: $error\n$stackTrace');
      _atlas = null;
      _spriteArtLoaded = false;
    }

    try {
      final pictureInfo = await vg.loadPicture(
        SvgAssetLoader(_characterSvgAsset),
        null,
      );
      _characterPicture = pictureInfo.picture;
      _characterArtLoaded = true;
    } catch (error, stackTrace) {
      debugPrint('Failed to load player SVG: $error\n$stackTrace');
      _characterArtLoaded = false;
      _characterPicture = null;
    }
  }

  // --- Acciones -------------------------------------------------------------

  /// Mueve un carril hacia la izquierda (-1) o la derecha (+1).
  void moveLane(int dir) {
    lane = (lane + dir).clamp(-1, 1);
  }

  /// Lo empuja hacia [newLane] (choque contra un camión): cambia de carril
  /// más rápido un instante.
  void bounceTo(int newLane) {
    lane = newLane.clamp(-1, 1);
    bounceTimer = bounceDuration;
  }

  /// Salta. Solo desde el suelo y sin agachado activo.
  bool jump() {
    if (isAirborne || isRolling) return false;
    jumpV = jumpSpeed;
    return true;
  }

  /// Se agachado. En el aire dispara una caída rápida y rueda al tocar el
  /// suelo (como el "dive" de Subway Surfers).
  bool roll() {
    if (isAirborne) {
      jumpV = -diveSpeed;
      _pendingRoll = true;
      return true;
    }
    if (isRolling) return false;
    rollTimer = rollDuration;
    return true;
  }

  /// Reinicia la partida: carril central, en el suelo, sin agachado.
  void resetTo({required Vector2 startPosition}) {
    lane = 0;
    lanePos = 0;
    jumpY = 0;
    jumpV = 0;
    groundHeight = 0;
    bounceTimer = 0;
    rollTimer = 0;
    _pendingRoll = false;
    blinkAlpha = 1;
    runRate = 1;
    _runPhase = 0;
    _airTime = 0;
    _landTimer = 0;
    _lean = 0;
    _groundY = startPosition.y;
    _syncGeometry();
  }

  /// Cambia la fila de suelo (al redimensionar la ventana) sin tocar el
  /// carril ni el salto en curso.
  void setGroundY(double y) {
    _groundY = y;
    _syncGeometry();
  }

  // --- Ciclo -----------------------------------------------------------------

  @override
  void update(double dt) {
    super.update(dt);

    // Carril: avanza a velocidad constante hasta el objetivo ("snap").
    final target = lane.toDouble();
    if (bounceTimer > 0) bounceTimer -= dt;
    if (lanePos != target) {
      final step = laneSpeed * (bounceTimer > 0 ? bounceBoost : 1.0) * dt;
      if ((target - lanePos).abs() <= step) {
        lanePos = target;
      } else {
        lanePos += step * (target > lanePos ? 1 : -1);
      }
    }

    // Salto: integración semi-implícita de la parábola.
    final wasAirborne = isAirborne;
    if (isAirborne) {
      jumpV -= gravity * dt;
      jumpY += jumpV * dt;
      if (jumpY <= groundHeight) {
        jumpY = groundHeight;
        jumpV = 0;
        if (_pendingRoll) {
          _pendingRoll = false;
          rollTimer = rollDuration;
        }
      }
    } else {
      // Apoyado: acompaña la superficie hacia arriba (rampa). Si la
      // superficie se fue, `isAirborne` ya da true y cae por gravedad.
      jumpY = groundHeight;
    }

    if (rollTimer > 0) rollTimer -= dt;

    // --- Animación ----------------------------------------------------------
    _airTime = isAirborne ? _airTime + dt : 0;
    if (wasAirborne && !isAirborne && !isRolling) _landTimer = _landDuration;
    if (_landTimer > 0) _landTimer -= dt;
    // Las piernas solo corren con los pies en el suelo y a ritmo del mundo.
    if (!isAirborne && !isRolling) {
      _runPhase = (_runPhase + dt * _runFps * runRate) % _runFrames;
    }
    // Inclinación al cambiar de carril: hacia donde va y suavizada.
    final wantLean = isRolling
        ? 0.0
        : (lane - lanePos).clamp(-1.0, 1.0).toDouble() * _maxLean;
    _lean += (wantLean - _lean) * math.min(1.0, dt * 16);

    _poseTime += dt;
    _syncGeometry();
  }

  /// Cuadro del atlas que corresponde al estado actual: carrera, las fases del
  /// salto (impulso, subida, punto más alto, caída, aterrizaje) o el agachado.
  @visibleForTesting
  int get poseFrame {
    if (isRolling) {
      final p = 1 - (rollTimer / rollDuration).clamp(0.0, 1.0);
      if (p < 0.16) return _slideIn;
      if (p > 0.84) return _slideOut;
      // En el medio alterna dos cuadros: el "trote" agachado.
      return (_poseTime * 11).floor().isEven ? _slideA : _slideB;
    }
    if (isAirborne) {
      // Caída rápida (agacharse en el aire): ya va encogido.
      if (_pendingRoll) return _slideIn;
      if (_airTime < _takeoffDuration && jumpV > 0) return _jumpCrouch;
      if (jumpV > _apexBand) return _jumpRise;
      if (jumpV < -_apexBand) return _jumpFall;
      return _jumpApex;
    }
    if (_landTimer > 0) return _landing;
    return _runPhase.floor() % _runFrames;
  }

  /// Inclinación actual por cambio de carril, en radianes.
  @visibleForTesting
  double get lean => _lean;

  void _syncGeometry() {
    // La profundidad es la del suelo: la X del carril no varía al saltar.
    final t = perspective.tAtY(_groundY);
    position.setValues(
      perspective.xAtT(lanePos, t),
      _groundY - jumpY,
    );
  }

  // --- Dibujo ----------------------------------------------------------------

  @override
  void render(Canvas canvas) {
    if (hasCustomArt) {
      if (_atlas != null && _spriteArtLoaded) {
        _renderAtlasCharacter(canvas);
      } else {
        _renderSvgCharacter(canvas);
      }
      return;
    }

    // El parpadeo de la invulnerabilidad baja la opacidad de todo el cuerpo.
    final body = _bodyColor.withValues(alpha: blinkAlpha.clamp(0.0, 1.0));
    _paint.color = body;
    _stroke.color = body;

    final cx = size.x * 0.5;

    if (isRolling) {
      // Agachado: masa baja y redondeada (se lo ve de espaldas).
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(cx - 13, 17, 26, 15),
          topLeft: const Radius.circular(8),
          topRight: const Radius.circular(8),
          bottomLeft: const Radius.circular(4),
          bottomRight: const Radius.circular(4),
        ),
        _paint,
      );
      canvas.drawCircle(Offset(cx, 19), 5, _paint);
      return;
    }

    final airborne = isAirborne;
    canvas.drawCircle(Offset(cx, 6), 6, _paint);
    canvas.drawLine(Offset(cx, 12), Offset(cx, 26), _stroke);
    if (airborne) {
      // Brazos arriba al saltar.
      canvas.drawLine(Offset(cx, 17), Offset(cx - 9, 5), _paint);
      canvas.drawLine(Offset(cx, 17), Offset(cx + 9, 5), _paint);
    } else {
      canvas.drawLine(Offset(cx, 18), Offset(cx - 8, 24), _paint);
      canvas.drawLine(Offset(cx, 18), Offset(cx + 8, 24), _paint);
    }
    canvas.drawLine(Offset(cx, 26), Offset(cx - 6, 34), _paint);
    canvas.drawLine(Offset(cx, 26), Offset(cx + 6, 34), _paint);
  }

  final Paint _spritePaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _shadowPaint = Paint();

  void _renderAtlasCharacter(Canvas canvas) {
    final atlas = _atlas;
    if (atlas == null) return;

    final cx = size.x * 0.5;
    final frame = poseFrame;
    final col = frame % _atlasCols;
    final row = frame ~/ _atlasCols;
    final src = Rect.fromLTWH(col * _cell, row * _cell, _cell, _cell);

    // Sombra en el SUELO (no en el cuerpo): al saltar queda abajo y se achica y
    // se aclara con la altura, que es lo que da la sensación de salto.
    final lift = math.max(0.0, jumpY - groundHeight);
    final h = (lift / 110).clamp(0.0, 1.0);
    final groundY = size.y + lift;
    final shadowW = playerSize * (isRolling ? 1.15 : 0.95) * (1 - 0.35 * h);
    final shadowA = (0.30 * (1 - 0.55 * h)) * blinkAlpha.clamp(0.0, 1.0);
    _shadowPaint.color = const Color(0xFF0F172A).withValues(alpha: shadowA * 0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, groundY),
        width: shadowW * 1.35,
        height: shadowW * 0.46,
      ),
      _shadowPaint,
    );
    _shadowPaint.color = const Color(0xFF0F172A).withValues(alpha: shadowA);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, groundY),
        width: shadowW,
        height: shadowW * 0.3,
      ),
      _shadowPaint,
    );

    // Rebote de la carrera: sincronizado con los pasos (dos por ciclo), no un
    // vaivén libre. Y estirar al subir / alargar al caer para dar peso.
    var bob = 0.0;
    var stretchY = 1.0;
    var stretchX = 1.0;
    if (!isAirborne && !isRolling && _landTimer <= 0) {
      bob = -math.sin(_runPhase * math.pi / 2).abs() * 1.6;
    } else if (isAirborne && !_pendingRoll) {
      final v = (jumpV / jumpSpeed).clamp(-1.4, 1.0);
      stretchY = 1 + 0.05 * v.abs();
      stretchX = 1 - 0.035 * v.abs();
    }

    _spritePaint.color =
        Color.fromRGBO(255, 255, 255, blinkAlpha.clamp(0.0, 1.0));

    // Todo gira y escala alrededor de los PIES: así la inclinación no desplaza
    // al personaje hacia los costados.
    canvas.save();
    canvas.translate(cx, size.y + bob);
    canvas.rotate(_lean);
    canvas.scale(stretchX, stretchY);
    canvas.drawImageRect(
      atlas,
      src,
      Rect.fromLTWH(
        -(_cell * 0.5) * _drawScale,
        -_cellFeetY * _drawScale,
        _cell * _drawScale,
        _cell * _drawScale,
      ),
      _spritePaint,
    );
    canvas.restore();
  }

  void _renderSvgCharacter(Canvas canvas) {
    final picture = _characterPicture;
    if (picture == null) return;

    final bob = isAirborne ? 0.0 : (math.sin(_poseTime * 12.0) * 2.0);
    final stride = isAirborne ? 0.04 : math.sin(_poseTime * 10.0) * 0.08;
    final lean = isAirborne ? 0.14 : math.sin(_poseTime * 10.0) * 0.12;
    final rollBias = isRolling ? -0.28 : 0.0;

    const crop = Rect.fromLTWH(20, 12, 90, 182);

    canvas.save();
    canvas.translate(-size.x * 0.5, -size.y * 0.68 + bob);
    canvas.rotate(lean + rollBias);

    final shadow = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x * 0.5, size.y * 0.92),
        width: size.x * 0.72,
        height: size.y * 0.18,
      ),
      shadow,
    );

    canvas.clipRect(Rect.fromLTWH(0, 0, size.x, size.y * 1.8));

    final scale = (size.x / crop.width) * 0.9;
    canvas.scale(scale);
    canvas.translate(-crop.left + 2, -crop.top - 4 + (isRolling ? 16 : 0));
    canvas.translate(stride * 14, 0);
    canvas.drawPicture(picture);
    canvas.restore();
  }

  // --- Colisión --------------------------------------------------------------

  /// Caja real: mide [rollHeight] agachado y [playerSize] parado, anclada en
  /// los pies (que suben al saltar).
  Rect get hitBox {
    final h = bodyHeight;
    final bottom = position.y + playerSize * 0.5;
    return Rect.fromLTRB(
      position.x - playerSize * 0.35,
      bottom - h,
      position.x + playerSize * 0.35,
      bottom,
    );
  }
}
