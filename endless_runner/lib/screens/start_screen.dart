import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/game_state.dart';
import '../widgets/diamond_shop_modal.dart';
import '../widgets/menu_dialogs.dart';
import '../widgets/pixel_ui.dart';
import '../widgets/rewards_modal.dart';
import 'home_screen.dart';

/// Pantalla de inicio: la ilustración de Zombie Run de fondo y, encima, los
/// botones reales (JUGAR, LOGROS, RÉCORD y AJUSTES, más la billetera de
/// diamantes que abre la tienda).
///
/// El fondo es `in_zombie_run_menu.png`: la ilustración original sin los
/// botones dibujados, porque los de verdad son widgets (así dicen "JUGAR", se
/// pueden tocar y se acomodan a cualquier pantalla).
class StartScreen extends StatefulWidget {
  const StartScreen({super.key, required this.gameState});

  final GameState gameState;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen>
    with SingleTickerProviderStateMixin {
  static const String _asset = 'assets/images/in_zombie_run_menu.png';

  /// Latido suave del botón JUGAR.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached) {
      _precached = true;
      // Evita el parpadeo del primer cuadro mientras se decodifica el fondo.
      precacheImage(const AssetImage(_asset), context, onError: (_, __) {});
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _play() {
    // Partida limpia (el récord y la billetera se conservan).
    widget.gameState.resetRun();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (_, __, ___) => HomeScreen(gameState: widget.gameState),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.gameState;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF140E0C),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF140E0C),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final pad = MediaQuery.paddingOf(context);
            // Arriba quedan libres los chips de diamantes y ajustes.
            final layout = _MenuLayout(size, topReserve: pad.top + 64);

            // --- JUGAR -------------------------------------------------
            final playW = (layout.wide ? 520 * layout.scale : size.width * 0.72)
                .clamp(200.0, 460.0)
                .toDouble();
            final playH = playW / 3.4;

            // --- Botones secundarios ---------------------------------
            final bottomPad = math.max(pad.bottom, 8.0) + 14;
            final rowH = layout.wide
                ? (94 * layout.scale).clamp(46.0, 66.0).toDouble()
                : 54.0;
            final rowTop = size.height - bottomPad - rowH;

            final double playCx;
            final double playCy;
            if (layout.wide) {
              playCx = layout.x(762);
              playCy = layout.y(833);
            } else {
              playCx = size.width / 2;
              playCy = math.min(layout.y(833), rowTop - 20 - playH / 2);
            }

            final double sideW = layout.wide
                ? (280 * layout.scale).clamp(150.0, 300.0).toDouble()
                : (size.width - 40 - 14) / 2;
            final double leftX = layout.wide
                ? (layout.x(210) - sideW / 2)
                    .clamp(12.0, size.width - sideW - 12)
                    .toDouble()
                : 20.0;
            final double rightX = layout.wide
                ? (layout.x(1326) - sideW / 2)
                    .clamp(12.0, size.width - sideW - 12)
                    .toDouble()
                : 20.0 + sideW + 14;
            final double sideTop = layout.wide
                ? (layout.y(865) - rowH / 2)
                    .clamp(0.0, size.height - rowH - 8)
                    .toDouble()
                : rowTop;

            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(child: _Backdrop(layout: layout, asset: _asset)),

                // Diamantes (abre la tienda), arriba a la izquierda.
                Positioned(
                  top: pad.top + 12,
                  left: math.max(pad.left, 0.0) + 12,
                  child: ValueListenableBuilder<int>(
                    valueListenable: state.diamonds,
                    builder: (_, diamonds, __) => PixelButton(
                      semanticLabel: 'Tienda de diamantes',
                      pixel: 2,
                      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                      onTap: () => showDiamondShopModal(context, state),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.diamond_rounded,
                              size: 18, color: PixelStyle.gem),
                          const SizedBox(width: 8),
                          Text('$diamonds', style: PixelStyle.text(11)),
                          const SizedBox(width: 8),
                          const Icon(Icons.add_box_rounded,
                              size: 16, color: PixelStyle.plankTop),
                        ],
                      ),
                    ),
                  ),
                ),

                // Ajustes, arriba a la derecha.
                Positioned(
                  top: pad.top + 12,
                  right: math.max(pad.right, 0.0) + 12,
                  child: PixelButton(
                    semanticLabel: 'Ajustes',
                    padding: const EdgeInsets.all(10),
                    onTap: () => showSettingsDialog(context, state),
                    child: const Icon(
                      Icons.settings_rounded,
                      size: 26,
                      color: PixelStyle.cream,
                    ),
                  ),
                ),

                // JUGAR.
                Positioned(
                  left: playCx - playW / 2,
                  top: playCy - playH / 2,
                  width: playW,
                  height: playH,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 1.045).animate(
                      CurvedAnimation(
                        parent: _pulse,
                        curve: Curves.easeInOut,
                      ),
                    ),
                    child: PixelButton(
                      semanticLabel: 'Jugar',
                      pixel: playH / 20,
                      fill: const [PixelStyle.plankTop, PixelStyle.plankBottom],
                      border: PixelStyle.plankBorder,
                      edge: const Color(0xFFFFE27A),
                      padding: EdgeInsets.zero,
                      onTap: _play,
                      child: Center(
                        child: Text(
                          'JUGAR',
                          style: PixelStyle.text(
                            playH * 0.3,
                            color: PixelStyle.plankInk,
                            shadows: const [
                              Shadow(
                                color: Color(0x80FFF0B0),
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // LOGROS.
                Positioned(
                  left: leftX,
                  top: sideTop,
                  width: sideW,
                  height: rowH,
                  child: _AchievementsButton(gameState: state),
                ),

                // RÉCORD.
                Positioned(
                  left: rightX,
                  top: sideTop,
                  width: sideW,
                  height: rowH,
                  child: _MenuButton(
                    label: 'RÉCORD',
                    icon: Icons.leaderboard_rounded,
                    onTap: () => showRecordDialog(context, state),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Geometría del fondo: la ilustración (1536×1024) se escala para que se vea
/// el logo y el corredor completos.
///
///  - En un celular vertical muestra una franja centrada en el logo/corredor
///    (los costados se recortan) y el cielo sobrante se completa arriba.
///  - En una pantalla apaisada muestra la imagen entera (o casi) y, si sobra
///    ancho, los costados se completan con el color del borde.
class _MenuLayout {
  _MenuLayout(this.size, {this.topReserve = 0}) {
    wide = size.width / size.height >= 1.2;
    final cover = math.max(size.width / srcW, size.height / srcH);
    // Alto que se puede usar: en apaisado alcanza con ver del logo a los
    // botones; en vertical la imagen entera tiene que entrar debajo de los
    // chips de arriba (el cielo sobrante se completa por encima).
    final fitH =
        wide ? size.height / needH : (size.height - topReserve) / srcH;
    scale = math.min(cover, math.min(size.width / minVisible, fitH));
    imgW = srcW * scale;
    imgH = srcH * scale;
    left = imgW <= size.width
        ? (size.width - imgW) / 2
        : (size.width / 2 - focusX * scale)
            .clamp(size.width - imgW, 0.0)
            .toDouble();
    top = imgH >= size.height
        ? (size.height / 2 - focusY * scale)
            .clamp(size.height - imgH, 0.0)
            .toDouble()
        : size.height - imgH;
  }

  static const double srcW = 1536;
  static const double srcH = 1024;

  /// Centro horizontal del logo y del corredor, en píxeles de la imagen.
  static const double focusX = 760;
  static const double focusY = 480;

  /// Ancho mínimo de imagen que se quiere ver (el logo mide ~565 px).
  static const double minVisible = 580;

  /// Alto mínimo que se quiere ver (del logo a los botones).
  static const double needH = 900;

  final Size size;

  /// Alto de arriba que debe quedar libre (barra de estado + chips).
  final double topReserve;
  late final double scale;
  late final double imgW;
  late final double imgH;
  late final double left;
  late final double top;
  late final bool wide;

  double get right => size.width - (left + imgW);

  double x(double srcX) => left + srcX * scale;
  double y(double srcY) => top + srcY * scale;
}

/// Fondo: relleno de bordes + ilustración.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.layout, required this.asset});

  final _MenuLayout layout;
  final String asset;

  // Color de la primera fila de la imagen y su versión más profunda, para
  // seguir el cielo hacia arriba cuando sobra alto.
  static const Color _skyEdge = Color(0xFF726298);
  static const Color _skyDeep = Color(0xFF3A2F6B);

  // Color de las columnas laterales a seis alturas, para completar los
  // costados cuando sobra ancho.
  static const List<Color> _edgeLeft = [
    Color(0xFFAB7287),
    Color(0xFFDB795B),
    Color(0xFFC75937),
    Color(0xFF56371A),
    Color(0xFF5E2F22),
    Color(0xFF703A31),
  ];
  static const List<Color> _edgeRight = [
    Color(0xFFA8728D),
    Color(0xFFBF6B49),
    Color(0xFF703D2D),
    Color(0xFF672D16),
    Color(0xFF954623),
    Color(0xFF733C30),
  ];

  Widget _fill(List<Color> colors) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = layout;
    return Stack(
      children: [
        if (l.top > 0.5)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: l.top + 1,
            child: _fill(const [_skyDeep, _skyEdge]),
          ),
        if (l.left > 0.5)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: l.left + 1,
            child: _fill(_edgeLeft),
          ),
        if (l.right > 0.5)
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: l.right + 1,
            child: _fill(_edgeRight),
          ),
        Positioned(
          left: l.left,
          top: l.top,
          width: l.imgW,
          height: l.imgH,
          child: Image.asset(
            asset,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF726298), Color(0xFFE9803A), Color(0xFF3A2220)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Botón oscuro con ícono y texto (LOGROS, RÉCORD).
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final fontSize = (c.maxHeight * 0.26).clamp(10.0, 15.0).toDouble();
        return PixelButton(
          semanticLabel: label,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          onTap: onTap,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: fontSize * 1.8, color: PixelStyle.cream),
                SizedBox(width: fontSize * 0.7),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: PixelStyle.text(fontSize),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// LOGROS con un globito rojo cuando hay premios para cobrar.
class _AchievementsButton extends StatelessWidget {
  const _AchievementsButton({required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: _MenuButton(
            label: 'LOGROS',
            icon: Icons.emoji_events_rounded,
            onTap: () => showRewardsModal(context, gameState),
          ),
        ),
        Positioned(
          top: -8,
          right: -6,
          child: ValueListenableBuilder<int>(
            valueListenable: gameState.claimable,
            builder: (_, n, __) => n <= 0
                ? const SizedBox.shrink()
                : IgnorePointer(
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 24, minHeight: 24),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: PixelStyle.alert,
                        border: Border.all(color: PixelStyle.ink, width: 2),
                      ),
                      child: Text(
                        '$n',
                        style: PixelStyle.text(10, color: Colors.white, height: 1),
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}
