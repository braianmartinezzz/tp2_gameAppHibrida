import 'package:flutter/material.dart';
import '../state/game_state.dart';
import '../state/rewards.dart';
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
                          'Tienda',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Mejoras con diamantes · las compras son simuladas',
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
              Text(
                'Mejoras',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              _UpgradesSection(gameState: gameState),
              const SizedBox(height: 18),
              Text(
                'Comprar diamantes',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
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

/// Mejoras que se pagan con diamantes. Se redibuja sola al comprar.
class _UpgradesSection extends StatelessWidget {
  const _UpgradesSection({required this.gameState});

  final GameState gameState;

  static const _icons = {
    UpgradeIds.startShield: Icons.shield_rounded,
    UpgradeIds.magnet: Icons.compass_calibration_rounded,
    UpgradeIds.multiplier: Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable:
          Listenable.merge([gameState.upgradeLevels, gameState.diamonds]),
      builder: (context, _) {
        return Column(
          children: [
            for (final def in kUpgrades)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _UpgradeTile(
                  def: def,
                  icon: _icons[def.id] ?? Icons.star_rounded,
                  level: gameState.upgradeLevel(def.id),
                  balance: gameState.diamonds.value,
                  onBuy: () => gameState.buyUpgrade(def),
                  theme: theme,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.def,
    required this.icon,
    required this.level,
    required this.balance,
    required this.onBuy,
    required this.theme,
  });

  final UpgradeDef def;
  final IconData icon;
  final int level;
  final int balance;
  final VoidCallback onBuy;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final maxed = level >= def.maxLevel;
    final cost = maxed ? 0 : def.costs[level];
    final affordable = balance >= cost;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.title,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  def.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < def.maxLevel; i++)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        width: 18,
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: i < level
                              ? AppColors.play
                              : theme.colorScheme.outlineVariant,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (maxed)
            const Text('MÁX',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: AppColors.play))
          else
            FilledButton.icon(
              onPressed: affordable ? onBuy : null,
              icon: const Icon(Icons.diamond_rounded, size: 16),
              label: Text('$cost'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 38),
              ),
            ),
        ],
      ),
    );
  }
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
