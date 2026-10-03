import 'package:flutter/material.dart';
import '../state/game_state.dart';
import 'diamond_shop_modal.dart';

class GameHeader extends StatelessWidget {
  const GameHeader({super.key, required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                const Icon(Icons.person_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: gameState.username,
                  builder: (_, name, __) => Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: gameState.score,
                  builder: (_, score, __) => Text(
                    'score: $score',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<int>(
            valueListenable: gameState.bestScore,
            builder: (_, best, __) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events_rounded,
                      size: 14, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 4),
                  Text(
                    'BEST $best',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onPrimaryContainer,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<String>(
            valueListenable: gameState.accountType,
            builder: (_, type, __) => Chip(
              label: Text(type.toUpperCase()),
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showDiamondShopModal(context, gameState),
            child: ValueListenableBuilder<int>(
              valueListenable: gameState.diamonds,
              builder: (_, diamonds, __) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    Icon(Icons.diamond_rounded,
                        size: 16, color: scheme.onSecondaryContainer),
                    const SizedBox(width: 4),
                    Text(
                      '$diamonds',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSecondaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
