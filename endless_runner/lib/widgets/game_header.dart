import 'package:flutter/material.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'diamond_shop_modal.dart';
import 'pixel_ui.dart';
import 'pro_upgrade_modal.dart';

/// Barra superior: avatar, usuario, score, tipo de cuenta y diamantes.
///
/// Panel marrón oscuro con la fuente pixel y una línea naranja abajo, como
/// los paneles de la pantalla de inicio (se ve igual en modo claro y oscuro,
/// solo cambia el tono del marrón). Sombra dura, sin degradés suaves.
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: const Border(
          bottom: BorderSide(color: AppColors.ember, width: 4),
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), offset: Offset(0, 4)),
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
                  builder: (_, name, __) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      name,
                      maxLines: 1,
                      style: PixelStyle.text(
                        12,
                        color: PixelStyle.cream,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: PixelStyle.panelEdge, width: 2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.gold),
                      const SizedBox(width: 4),
                      Flexible(
                        child: ValueListenableBuilder<int>(
                          valueListenable: gameState.score,
                          builder: (_, score, __) => FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'score: $score',
                              style: PixelStyle.text(
                                9,
                                color: PixelStyle.cream,
                                height: 1.0,
                              ),
                            ),
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
          GestureDetector(
            key: const ValueKey('account-badge'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              onBeforeShop?.call();
              showProUpgradeModal(context, gameState);
            },
            child: ValueListenableBuilder<String>(
              valueListenable: gameState.accountType,
              builder: (_, type, __) => _AccountBadge(type: type),
            ),
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PixelStyle.cream,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PixelStyle.ink, width: 2),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          gradient: const LinearGradient(
            colors: [PixelStyle.plankTop, PixelStyle.plankBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: const Icon(
          Icons.person_rounded,
          color: PixelStyle.plankInk,
          size: 26,
        ),
      ),
    );
  }
}

/// BASIC (translúcido) o PRO (tablón dorado con corona).
class _AccountBadge extends StatelessWidget {
  const _AccountBadge({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final pro = type == 'pro';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        gradient: pro
            ? const LinearGradient(
                colors: [PixelStyle.plankTop, PixelStyle.plankBottom],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              )
            : null,
        color: pro ? null : PixelStyle.cream.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: pro ? PixelStyle.plankBorder : PixelStyle.panelEdge,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pro ? Icons.workspace_premium_rounded : Icons.arrow_circle_up_rounded,
            size: 14,
            color: pro ? PixelStyle.plankInk : PixelStyle.cream,
          ),
          const SizedBox(width: 4),
          Text(
            type.toUpperCase(),
            style: PixelStyle.text(
              9,
              color: pro ? PixelStyle.plankInk : PixelStyle.cream,
              height: 1.0,
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
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gem, AppColors.gemDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.ink, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, size: 16, color: AppColors.ink),
          const SizedBox(width: 4),
          Text(
            '$diamonds',
            style: PixelStyle.text(11, color: AppColors.ink, height: 1.0),
          ),
          const SizedBox(width: 6),
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(3),
            ),
            child:
                const Icon(Icons.add_rounded, size: 16, color: AppColors.gem),
          ),
        ],
      ),
    );
  }
}
