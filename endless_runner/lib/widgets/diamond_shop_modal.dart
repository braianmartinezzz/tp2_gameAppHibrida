import 'package:flutter/material.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';

/// Monetización simulada con packs, precio ficticio y CTA de compra.
void showDiamondShopModal(BuildContext context, GameState gameState) {
  const packs = [
    _DiamondPack(
      amount: 100,
      label: 'Starter',
      price: '\$1.99',
      accent: Color(0xFF22C7E8),
      gems: 1,
    ),
    _DiamondPack(
      amount: 500,
      label: 'Boost',
      price: '\$4.99',
      accent: Color(0xFFFFA726),
      gems: 2,
      tag: 'POPULAR',
    ),
    _DiamondPack(
      amount: 1200,
      label: 'Pro',
      price: '\$9.99',
      accent: Color(0xFFA06BFF),
      gems: 3,
      tag: 'MEJOR VALOR',
    ),
  ];

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (context) {
      final theme = Theme.of(context);
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [AppColors.gem, AppColors.gemDeep],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: const Icon(Icons.diamond_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comprar diamantes',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Compra simulada: no se cobra nada',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...packs.map(
                (pack) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PackCard(
                    pack: pack,
                    onBuy: () {
                      gameState.addDiamonds(pack.amount);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.pack, required this.onBuy});

  final _DiamondPack pack;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onBuy,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    pack.accent.withValues(alpha: 0.20),
                    pack.accent.withValues(alpha: 0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: pack.accent.withValues(alpha: 0.7),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  _GemStack(gems: pack.gems, color: pack.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${pack.amount} diamantes',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          pack.label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: onBuy,
                    style: FilledButton.styleFrom(
                      backgroundColor: pack.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(pack.price),
                  ),
                ],
              ),
            ),
            if (pack.tag != null)
              Positioned(
                top: -9,
                right: 18,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: pack.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    pack.tag!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Medallón con 1 a 3 gemas: cuanto más grande el pack, más gemas.
class _GemStack extends StatelessWidget {
  const _GemStack({required this.gems, required this.color});

  final int gems;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.18),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (gems >= 2) ...[
            Positioned(
              left: 5,
              bottom: 10,
              child: Icon(Icons.diamond_rounded,
                  size: 20, color: color.withValues(alpha: 0.7)),
            ),
            Positioned(
              right: 5,
              bottom: 10,
              child: Icon(Icons.diamond_rounded,
                  size: 20, color: color.withValues(alpha: 0.7)),
            ),
          ],
          Icon(
            Icons.diamond_rounded,
            size: gems >= 3 ? 34 : 30,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _DiamondPack {
  const _DiamondPack({
    required this.amount,
    required this.label,
    required this.price,
    required this.accent,
    required this.gems,
    this.tag,
  });

  final int amount;
  final String label;
  final String price;
  final Color accent;
  final int gems;
  final String? tag;
}
