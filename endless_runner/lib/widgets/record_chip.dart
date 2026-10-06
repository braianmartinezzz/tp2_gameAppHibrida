import 'package:flutter/material.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';

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
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF140E0C).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: gameState.bestScore,
        builder: (_, best, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.gold, AppColors.goldDeep],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: const Icon(
                Icons.emoji_events_rounded,
                size: 13,
                color: AppColors.goldInk,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Récord $best',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
