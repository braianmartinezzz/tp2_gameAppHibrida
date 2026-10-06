import 'package:flutter/material.dart';

import '../audio/game_sfx.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'back_arrow.dart';
import 'purchase_flow.dart';

/// Menú "Mejorar a Pro": lista los beneficios, muestra el precio y simula el
/// pago con el mismo flujo que los packs de diamantes ([showPurchaseFlow]:
/// resumen, puerta parental, "procesando" y resultado). Si la cuenta ya es
/// Pro, solo muestra los beneficios activos (sin botón de compra). La compra
/// es simulada: no hay cobro real.
Future<void> showProUpgradeModal(BuildContext context, GameState gameState) {
  if (gameState.isPro) {
    GameSfx.instance.play(Sfx.open);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => const _AlreadyPro(),
    );
  }
  return showPurchaseFlow(
    context,
    PurchaseItem(
      title: 'Mejorar a Pro',
      price: GameState.proPrice,
      icon: const _Crown(),
      summary: const _Benefits(),
      onPaid: gameState.upgradeToPro,
      successTitle: '¡Ya sos Pro!',
      successSubtitle: 'Beneficios desbloqueados',
      successBody: const _Benefits(),
      doneLabel: '¡A jugar!',
    ),
  );
}

/// Vista para quien ya es Pro: sus beneficios activos.
class _AlreadyPro extends StatelessWidget {
  const _AlreadyPro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: SubtleBackArrow(),
            ),
            const Center(child: _Crown()),
            const SizedBox(height: 12),
            Text(
              'Tu cuenta es Pro',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(
              'Estos son tus beneficios activos',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            const _Benefits(),
            const SizedBox(height: 8),
            FilledButton(
              key: const ValueKey('pro-done-button'),
              onPressed: sfxTap(() => Navigator.of(context).pop(), sfx: Sfx.back),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Crown extends StatelessWidget {
  const _Crown({this.size = 64});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [AppColors.gold, AppColors.goldDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Icon(Icons.workspace_premium_rounded,
          color: AppColors.goldInk, size: size * 0.58),
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.goldDeep, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _Benefit(
          icon: Icons.block_rounded,
          title: 'Sin anuncios',
          subtitle: 'Reiniciá y revivís sin ver publicidad',
        ),
        _Benefit(
          icon: Icons.favorite_rounded,
          title: '3 corazones por partida',
          subtitle: 'Un corazón extra en cada carrera (basic: 2)',
        ),
        _Benefit(
          icon: Icons.workspace_premium_rounded,
          title: 'Insignia PRO dorada',
          subtitle: 'Se luce en el encabezado',
        ),
      ],
    );
  }
}
