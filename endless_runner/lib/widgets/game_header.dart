import 'package:flutter/material.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'diamond_shop_modal.dart';

/// Barra superior: avatar, usuario, score, tipo de cuenta y diamantes.
///
/// Degradé violeta con texto blanco (se ve igual en modo claro y oscuro),
/// esquinas redondeadas abajo y una sombra suave que la separa del juego.
class GameHeader extends StatelessWidget {
  const GameHeader({super.key, required this.gameState, this.onBeforeShop});

  final GameState gameState;

  /// Se llama justo antes de abrir la tienda (la pantalla pausa la partida).
  final VoidCallback? onBeforeShop;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? AppColors.headerDark : AppColors.headerLight;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: colors.last.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const _Avatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<String>(
                  valueListenable: gameState.username,
                  builder: (_, name, __) => Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.gold),
                      const SizedBox(width: 3),
                      ValueListenableBuilder<int>(
                        valueListenable: gameState.score,
                        builder: (_, score, __) => Text(
                          'score: $score',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ValueListenableBuilder<String>(
            valueListenable: gameState.accountType,
            builder: (_, type, __) => _AccountBadge(type: type),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              onBeforeShop?.call();
              showDiamondShopModal(context, gameState);
            },
            child: ValueListenableBuilder<int>(
              valueListenable: gameState.diamonds,
              builder: (_, diamonds, __) => _DiamondPill(diamonds: diamonds),
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(2.5),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFFFF8FA3), Color(0xFFFFB86B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}

/// BASIC (translúcido) o PRO (dorado con corona).
class _AccountBadge extends StatelessWidget {
  const _AccountBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final pro = type == 'pro';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        gradient: pro
            ? const LinearGradient(
                colors: [AppColors.gold, AppColors.goldDeep],
              )
            : null,
        color: pro ? null : Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: pro
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pro) ...[
            const Icon(Icons.workspace_premium_rounded,
                size: 14, color: AppColors.goldInk),
            const SizedBox(width: 3),
          ],
          Text(
            type.toUpperCase(),
            style: TextStyle(
              color: pro ? AppColors.goldInk : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

/// Saldo de diamantes con un "+" que invita a abrir la tienda.
class _DiamondPill extends StatelessWidget {
  const _DiamondPill({required this.diamonds});

  final int diamonds;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 4, 4, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gem, AppColors.gemDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.gemDeep.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            '$diamonds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 20,
            height: 20,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_rounded,
                size: 16, color: AppColors.gemDeep),
          ),
        ],
      ),
    );
  }
}
