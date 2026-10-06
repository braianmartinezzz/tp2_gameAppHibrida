import 'package:flutter/material.dart';

import '../audio/game_sfx.dart';

/// Flecha de "volver" discreta: un círculo casi transparente con el chevrón a
/// media opacidad. Se ve lo justo para encontrarla sin competir con el
/// contenido, pero el área tocable es de 40 px.
///
/// Sin [onPressed] cierra la pantalla actual (`maybePop`, que respeta los
/// `PopScope`, como el de "procesando pago"). Suena [Sfx.back].
class SubtleBackArrow extends StatelessWidget {
  const SubtleBackArrow({
    super.key,
    this.onPressed,
    this.color,
    this.semanticLabel = 'Volver',
  });

  final VoidCallback? onPressed;

  /// Color base (por defecto, el del texto del tema). Sobre fondos oscuros o
  /// de color se le pasa uno claro.
  final Color? color;

  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final base = color ?? Theme.of(context).colorScheme.onSurface;
    final action = onPressed ?? () => Navigator.of(context).maybePop();
    return IconButton(
      tooltip: semanticLabel,
      onPressed: sfxCallback(action, sfx: Sfx.back),
      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 17),
      style: IconButton.styleFrom(
        foregroundColor: base.withValues(alpha: 0.62),
        backgroundColor: base.withValues(alpha: 0.08),
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const CircleBorder(),
      ),
    );
  }
}
