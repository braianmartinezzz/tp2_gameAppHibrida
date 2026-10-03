import 'package:flutter/material.dart';
import '../state/game_state.dart';

/// Monetización simulada con packs, precio ficticio y CTA de compra.
void showDiamondShopModal(BuildContext context, GameState gameState) {
  final packs = [
    _DiamondPack(
        amount: 100, label: 'Starter', price: '\$1.99', accent: Colors.cyan),
    _DiamondPack(
        amount: 500, label: 'Boost', price: '\$4.99', accent: Colors.amber),
    _DiamondPack(
        amount: 1200, label: 'Pro', price: '\$9.99', accent: Colors.purple),
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.shopping_bag_rounded,
                      color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Comprar diamantes',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...packs.map((pack) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        gameState.addDiamonds(pack.amount);
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          color: theme.colorScheme.surfaceContainerHighest,
                          border: Border.all(
                              color: theme.colorScheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: pack.accent.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.diamond_rounded,
                                color: pack.accent,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${pack.amount} diamantes',
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    pack.label,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            FilledButton(
                              onPressed: () {
                                gameState.addDiamonds(pack.amount);
                                Navigator.of(context).pop();
                              },
                              child: Text(pack.price),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      );
    },
  );
}

class _DiamondPack {
  const _DiamondPack({
    required this.amount,
    required this.label,
    required this.price,
    required this.accent,
  });

  final int amount;
  final String label;
  final String price;
  final Color accent;
}
