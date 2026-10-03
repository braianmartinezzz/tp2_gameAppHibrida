import 'package:flutter/material.dart';

import '../state/game_state.dart';

/// Etiqueta con el récord mientras se corre (Fase 4).
///
/// Vive sobre el corredor, arriba a la izquierda, para no pisar el HUD de
/// power-ups que el canvas dibuja en la derecha — y sin tocar GameHeader.
class RecordChip extends StatelessWidget {
  const RecordChip({super.key, required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    // Semitransparente fijo a propósito: el chip se ve igual sobre la calle
    // clara y sobre la oscura, sin depender del tema de la app.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: gameState.bestScore,
        builder: (_, best, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 14,
              color: Colors.amber,
            ),
            const SizedBox(width: 5),
            Text(
              'Récord $best',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
