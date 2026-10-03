import 'dart:async';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Publicidad simulada tipo modal con countdown y formato de anuncio.
/// Se muestra cada vez que se reinicia la partida (requisito de la consigna).
Future<void> showAdModal(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Anuncio',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => const SafeArea(child: _AdModalContent()),
    // Entrada: fundido + escala suave; salida: el mismo recorrido a la inversa.
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _AdModalContent extends StatefulWidget {
  const _AdModalContent();

  @override
  State<_AdModalContent> createState() => _AdModalContentState();
}

class _AdModalContentState extends State<_AdModalContent> {
  static const int _total = 3;

  int _secondsLeft = _total;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _secondsLeft = (_secondsLeft - 1).clamp(0, _total);
      });
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canClose = _secondsLeft <= 0;
    final progress = (_total - _secondsLeft) / _total;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      actionsPadding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      title: Row(
        children: [
          Icon(Icons.campaign_rounded,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text(
            'Anuncio simulado',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Pieza" publicitaria falsa: degradé, botón de play y etiqueta.
          Container(
            height: 140,
            width: double.maxFinite,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFFFF6B8A), Color(0xFFFFB020)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'PUBLICIDAD',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      size: 42,
                      color: Color(0xFFFF6B8A),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Barra de progreso: se llena a medida que corre el countdown.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 900),
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: AppColors.play,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canClose ? () => Navigator.of(context).pop() : null,
            child: Text(canClose ? 'Cerrar' : 'Cerrar (${_secondsLeft}s)'),
          ),
        ),
      ],
    );
  }
}
