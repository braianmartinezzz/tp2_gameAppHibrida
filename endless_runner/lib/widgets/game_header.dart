import 'package:flutter/material.dart';
import '../state/game_state.dart';
import 'diamond_shop_modal.dart';

class GameHeader extends StatelessWidget {
  const GameHeader({super.key, required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 18, child: Icon(Icons.face)),
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
              builder: (_, diamonds, __) => Row(
                children: [
                  const Icon(Icons.diamond, size: 16),
                  const SizedBox(width: 2),
                  Text('$diamonds'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
