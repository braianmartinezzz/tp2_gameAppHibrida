import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
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
  static const String _characterSpriteAsset =
      'assets/images/character/sprites_corredor.png';
  static const int _spriteCols = 4;
  static const int _spriteRows = 2;
  static const int _spriteFrameCount = 8;

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

  /// Altura sobre el suelo en px (0 = apoyado).
  double jumpY = 0;

  double jumpV = 0;

  /// Tiempo restante de agachado.
  double rollTimer = 0;

  bool _pendingRoll = false;
  double _poseTime = 0;

  double _groundY;

  /// Fila de suelo del jugador: la profundidad nunca cambia.
  double get groundY => _groundY;

  /// Y de los pies cuando está apoyado (referencia de colisión).
  double get groundFeetY => _groundY + playerSize * 0.5;

  bool get isAirborne => jumpY > 0 || jumpV != 0;
  bool get isRolling => rollTimer > 0;

  /// Alto real del cuerpo: 34 parado, [rollHeight] agachado.
  double get bodyHeight => isRolling ? rollHeight : playerSize;

  /// Color base del cuerpo.
  static const Color _bodyColor = Color(0xFF378ADD);

  /// Sprites del personaje cargados desde assets: la hoja de carreras se usa
  /// como art principal del corredor, con fallback al SVG y luego al dibujo
  /// geométrico viejo si falla la carga.
  ui.Image? _spriteSheet;
  bool _spriteArtLoaded = false;

  ui.Picture? _characterPicture;
  bool _characterArtLoaded = false;

  bool get hasCustomArt =>
      (_spriteArtLoaded && _spriteSheet != null) ||
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
    await _loadCharacterArt();
  }

  Future<void> _loadCharacterArt() async {
    try {
      final data = await rootBundle.load(_characterSpriteAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _spriteSheet = frame.image;
      _spriteArtLoaded = true;
      _characterArtLoaded = false;
      _characterPicture = null;
      return;
    } catch (error, stackTrace) {
      debugPrint('Failed to load player sprite sheet: $error\n$stackTrace');
      _spriteSheet = null;
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
    rollTimer = 0;
    _pendingRoll = false;
    blinkAlpha = 1;
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
    if (lanePos != target) {
      final step = laneSpeed * dt;
      if ((target - lanePos).abs() <= step) {
        lanePos = target;
      } else {
        lanePos += step * (target > lanePos ? 1 : -1);
      }
    }

    // Salto: integración semi-implícita de la parábola.
    if (isAirborne) {
      jumpV -= gravity * dt;
      jumpY += jumpV * dt;
      if (jumpY <= 0) {
        jumpY = 0;
        jumpV = 0;
        if (_pendingRoll) {
          _pendingRoll = false;
          rollTimer = rollDuration;
        }
      }
    }

    if (rollTimer > 0) rollTimer -= dt;

    _poseTime += dt;
    _syncGeometry();
  }

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
      if (_spriteSheet != null && _spriteArtLoaded) {
        _renderSpriteSheetCharacter(canvas);
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

  void _renderSpriteSheetCharacter(Canvas canvas) {
    final sheet = _spriteSheet;
    if (sheet == null) return;

    final frameW = sheet.width / _spriteCols;
    final frameH = sheet.height / _spriteRows;
    final frameIndex =
        (math.max(0.0, _poseTime * 10.0)).floor() % _spriteFrameCount;
    final col = frameIndex % _spriteCols;
    final row = (frameIndex / _spriteCols).floor();

    final src = Rect.fromLTWH(
      col * frameW,
      row * frameH,
      frameW,
      frameH,
    );

    final bob = isAirborne ? 0.0 : math.sin(_poseTime * 12.0) * 2.0;
    final lean = isAirborne ? 0.12 : math.sin(_poseTime * 10.0) * 0.12;
    final rollBias = isRolling ? -0.26 : 0.0;

    final dstW = size.x * 2.15;
    final dstH = frameH * (dstW / frameW);
    final spritePaint = Paint()..filterQuality = FilterQuality.high;

    canvas.save();
    canvas.translate(-size.x * 0.5, -dstH * 0.82 + bob);
    canvas.rotate(lean + rollBias);

    final shadow = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.x * 0.5, dstH * 0.98),
        width: size.x * 1.0,
        height: size.y * 0.16,
      ),
      shadow,
    );

    canvas.drawImageRect(
      sheet,
      src,
      Rect.fromLTWH(0, 0, dstW, dstH),
      spritePaint,
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
