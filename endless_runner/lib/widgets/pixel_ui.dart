import 'package:flutter/material.dart';

/// Estilo 8 bits de la pantalla de inicio y sus diálogos: paneles con las
/// esquinas "escalonadas", borde oscuro, luz arriba y la fuente Press Start 2P
/// (assets/fonts, licencia OFL). Todo se dibuja con formas, sin imágenes.
abstract final class PixelStyle {
  static const String font = 'PressStart2P';

  static const Color ink = Color(0xFF140E0C);
  static const Color panel = Color(0xFF1D1A1D);
  static const Color panelDeep = Color(0xFF151214);
  static const Color panelEdge = Color(0xFF4A3F3A);
  static const Color cream = Color(0xFFF3E6CF);
  static const Color creamDim = Color(0xFFB9AA94);

  static const Color plankTop = Color(0xFFFFC61F);
  static const Color plankBottom = Color(0xFFF08A0C);
  static const Color plankInk = Color(0xFF3B1F0E);
  static const Color plankBorder = Color(0xFF2A140A);

  static const Color alert = Color(0xFFD13B3B);
  static const Color gem = Color(0xFF46DDF2);

  /// Texto de la fuente pixel. [size] es el alto de cada letra: la fuente es
  /// monoespaciada y cada carácter ocupa [size] de ancho.
  static TextStyle text(
    double size, {
    Color color = cream,
    double height = 1.35,
    List<Shadow>? shadows,
  }) =>
      TextStyle(
        fontFamily: font,
        fontSize: size,
        color: color,
        height: height,
        letterSpacing: 0.5,
        shadows: shadows,
      );
}

/// Rectángulo con las esquinas recortadas en dos escalones de [p] píxeles.
Path pixelRectPath(Rect r, double p) {
  final l = r.left, t = r.top, rt = r.right, b = r.bottom;
  return Path()
    ..moveTo(l + 2 * p, t)
    ..lineTo(rt - 2 * p, t)
    ..lineTo(rt - 2 * p, t + p)
    ..lineTo(rt - p, t + p)
    ..lineTo(rt - p, t + 2 * p)
    ..lineTo(rt, t + 2 * p)
    ..lineTo(rt, b - 2 * p)
    ..lineTo(rt - p, b - 2 * p)
    ..lineTo(rt - p, b - p)
    ..lineTo(rt - 2 * p, b - p)
    ..lineTo(rt - 2 * p, b)
    ..lineTo(l + 2 * p, b)
    ..lineTo(l + 2 * p, b - p)
    ..lineTo(l + p, b - p)
    ..lineTo(l + p, b - 2 * p)
    ..lineTo(l, b - 2 * p)
    ..lineTo(l, t + 2 * p)
    ..lineTo(l + p, t + 2 * p)
    ..lineTo(l + p, t + p)
    ..lineTo(l + 2 * p, t + p)
    ..close();
}

/// Panel pixel-art: sombra, borde, relleno en degradé vertical, una línea
/// de luz arriba y otra de sombra abajo.
class PixelPanelPainter extends CustomPainter {
  const PixelPanelPainter({
    required this.fill,
    required this.border,
    this.pixel = 3,
    this.edge,
    this.shadow = true,
  });

  /// Colores del degradé (arriba → abajo).
  final List<Color> fill;
  final Color border;
  final double pixel;

  /// Línea fina más clara pegada al borde interior (opcional).
  final Color? edge;
  final bool shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final p = pixel;
    if (size.width < p * 8 || size.height < p * 8) return;
    final outer = Offset.zero & size;

    if (shadow) {
      canvas.drawPath(
        pixelRectPath(outer.shift(Offset(0, p)), p),
        Paint()..color = const Color(0x59000000),
      );
    }
    canvas.drawPath(pixelRectPath(outer, p), Paint()..color = border);

    final inner = outer.deflate(p);
    if (edge != null) {
      canvas.drawPath(pixelRectPath(inner, p), Paint()..color = edge!);
    }
    final body = edge != null ? inner.deflate(p * 0.75) : inner;
    canvas.drawPath(
      pixelRectPath(body, p),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: fill.length == 1 ? [fill.first, fill.first] : fill,
        ).createShader(body),
    );

    // Luz arriba y sombra abajo, un píxel de alto.
    canvas.drawRect(
      Rect.fromLTWH(body.left + 2 * p, body.top, body.width - 4 * p, p),
      Paint()..color = const Color(0x47FFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(body.left + 2 * p, body.bottom - p, body.width - 4 * p, p),
      Paint()..color = const Color(0x2E000000),
    );
  }

  @override
  bool shouldRepaint(PixelPanelPainter old) =>
      old.fill != fill ||
      old.border != border ||
      old.pixel != pixel ||
      old.edge != edge ||
      old.shadow != shadow;
}

/// Botón pixel-art: al apretarlo "se hunde" un píxel. Ocupa el tamaño que le
/// dé el padre (o el de su [child] si no hay restricciones).
class PixelButton extends StatefulWidget {
  const PixelButton({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.fill = const [PixelStyle.panel, PixelStyle.panelDeep],
    this.border = PixelStyle.ink,
    this.edge = PixelStyle.panelEdge,
    this.pixel = 3,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;
  final List<Color> fill;
  final Color border;
  final Color? edge;
  final double pixel;
  final EdgeInsetsGeometry padding;

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: Transform.translate(
          offset: Offset(0, _down ? widget.pixel : 0),
          child: CustomPaint(
            painter: PixelPanelPainter(
              fill: widget.fill,
              border: widget.border,
              edge: widget.edge,
              pixel: widget.pixel,
              shadow: !_down,
            ),
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// Muestra un diálogo con el estilo pixel: título, botón de cierre y [body].
Future<void> showPixelDialog(
  BuildContext context, {
  required String title,
  required Widget body,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.68),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: CustomPaint(
          painter: const PixelPanelPainter(
            fill: [Color(0xFF2A2322), Color(0xFF181314)],
            border: PixelStyle.ink,
            edge: PixelStyle.panelEdge,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: PixelStyle.text(15, color: PixelStyle.plankTop),
                      ),
                    ),
                    PixelButton(
                      semanticLabel: 'Cerrar',
                      onTap: () => Navigator.of(ctx).pop(),
                      padding: const EdgeInsets.all(6),
                      pixel: 2,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: PixelStyle.cream,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(child: SingleChildScrollView(child: body)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
