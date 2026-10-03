import 'package:flutter/material.dart';

import '../state/game_state.dart';

/// Resumen de la partida terminada (Fase 4): puntaje final, récord con su
/// medalla de "nuevo récord", diamantes ganados en la corrida y el botón para
/// reintentar.
///
/// Lo monta HomeScreen sobre el corredor cuando [GameState.isGameOver]; vive
/// por fuera de GameHeader y GameControls, que no se tocan.
///
/// Los valores se leen al construir (no con ValueListenableBuilder) porque la
/// partida está congelada: mientras este overlay está montado nada del estado
/// de la corrida vuelve a moverse hasta reiniciar.
class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({
    super.key,
    required this.gameState,
    required this.onRestart,
  });

  final GameState gameState;

  /// Camino de reinicio. En la app real pasa por el anuncio simulado (mismo
  /// requisito que la botonera externa); en los tests es un contador.
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = gameState.score.value;
    final best = gameState.bestScore.value;
    final newRecord = gameState.isNewRecord.value;
    final runDiamonds = gameState.runDiamonds.value;

    return Container(
      color: Colors.black.withValues(alpha: 0.55),
      alignment: Alignment.center,
      // Entrada: aparece con fundido y un rebote chiquito desde el centro.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.emoji_events_rounded,
                size: 36,
                color: newRecord ? Colors.amber : scheme.primary,
              ),
              const SizedBox(height: 8),
              Text(
                'PARTIDA TERMINADA',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
              ),
              const SizedBox(height: 16),
              _ResultRow(label: 'Puntaje', value: '$score', highlight: true),
              _ResultRow(label: 'Récord', value: '$best'),
              if (newRecord) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.45),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Text(
                    '¡NUEVO RÉCORD!',
                    style: TextStyle(
                      color: Color(0xFF3B2C00),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.diamond, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Ganaste $runDiamonds diamantes',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRestart,
                icon: const Icon(Icons.replay),
                label: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila del resumen: etiqueta a la izquierda, valor a la derecha.
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;

  /// true para el puntaje final, que se muestra más grande.
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: style.bodyMedium),
          const SizedBox(width: 20),
          Text(
            value,
            style: highlight
                ? style.headlineSmall?.copyWith(fontWeight: FontWeight.w900)
                : style.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
