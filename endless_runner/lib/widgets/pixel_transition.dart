import 'package:flutter/material.dart';
import 'pixel_ui.dart';

/// Transición 8 bits entre pantallas: un telón de bloques cuadrados "tapa" la
/// pantalla vieja con un barrido en diagonal (primera mitad), se cambia de
/// pantalla con todo tapado y el telón se retira por el mismo camino
/// (segunda mitad). Al volver (pop) corre al revés.
///
/// La pantalla nueva se construye desde el primer cuadro (para que el juego
/// ya tenga su tamaño y sus imágenes) pero no se ve ni recibe toques hasta
/// [revealAt]. Las pantallas pueden leer `ModalRoute.of(context).animation`
/// para sincronizar su propia entrada con ese momento.
class PixelDissolveRoute<T> extends PageRouteBuilder<T> {
  PixelDissolveRoute({
    required WidgetBuilder builder,
    Color color = PixelStyle.ink,
  }) : super(
          transitionDuration: const Duration(milliseconds: 780),
          reverseTransitionDuration: const Duration(milliseconds: 520),
          pageBuilder: (context, _, __) => builder(context),
          transitionsBuilder: (context, animation, _, child) =>
              _PixelDissolve(animation: animation, color: color, child: child),
        );

  /// Punto de la animación (0..1) en el que el telón está cerrado del todo:
  /// ahí se descubre la pantalla nueva.
  static const double revealAt = 0.5;
}

class _PixelDissolve extends StatelessWidget {
  const _PixelDissolve({
    required this.animation,
    required this.color,
    required this.child,
  });

  final Animation<double> animation;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final open = animation.value >= PixelDissolveRoute.revealAt;
        return Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              ignoring: !open,
              child: Opacity(
                key: const ValueKey('pixel-dissolve-page'),
                opacity: open ? 1 : 0,
                child: child,
              ),
            ),
            IgnorePointer(
              child: CustomPaint(
                painter: PixelCurtainPainter(
                  progress: animation.value,
                  color: color,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Telón de bloques. [progress] va de 0 a 1 como la animación de la ruta:
/// 0 y 1 = todo descubierto, [PixelDissolveRoute.revealAt] = todo tapado.
class PixelCurtainPainter extends CustomPainter {
  const PixelCurtainPainter({
    required this.progress,
    required this.color,
    this.cell = 24,
  });

  final double progress;
  final Color color;

  /// Lado de cada bloque, en px lógicos.
  final double cell;

  /// Cuánto del telón está cerrado (0..1) según el avance de la ruta.
  static double coverage(double progress) {
    const reveal = PixelDissolveRoute.revealAt;
    final c = progress < reveal
        ? progress / reveal
        : (1 - progress) / (1 - reveal);
    return c.clamp(0.0, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cover = coverage(progress);
    if (cover <= 0 || size.isEmpty) return;
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    final closing = progress < PixelDissolveRoute.revealAt;
    final span = (cols + rows - 2).clamp(1, 1 << 20);
    final paint = Paint()
      ..isAntiAlias = false
      ..color = color;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        // Orden en diagonal con un poco de desorden por bloque (aspecto de
        // "disolución" pixelada). Al abrir se invierte: los primeros en
        // taparse son los primeros en irse y el barrido sigue en el mismo
        // sentido.
        final jitter = (((c * 73856093) ^ (r * 19349663)) & 255) / 255 * 0.14;
        final order = ((c + r) / span) * 0.86 + jitter;
        final threshold = closing ? order : 1 - order;
        if (cover >= 1 || threshold <= cover) {
          canvas.drawRect(
            Rect.fromLTWH(c * cell, r * cell, cell + 0.5, cell + 0.5),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(PixelCurtainPainter old) =>
      old.progress != progress || old.color != color || old.cell != cell;
}
