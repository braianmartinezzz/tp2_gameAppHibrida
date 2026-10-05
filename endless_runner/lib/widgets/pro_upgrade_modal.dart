import 'package:flutter/material.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';

/// Menú "Mejorar a Pro": lista los beneficios, muestra el precio y simula el
/// pago. Si la cuenta ya es Pro, muestra los beneficios activos (sin botón de
/// compra). La compra es simulada: no hay cobro real.
Future<void> showProUpgradeModal(BuildContext context, GameState gameState) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Mientras "se procesa" el pago no se puede cerrar tocando afuera.
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (context) => _ProUpgradeSheet(gameState: gameState),
  );
}

enum _Phase { offer, processing, done }

class _ProUpgradeSheet extends StatefulWidget {
  const _ProUpgradeSheet({required this.gameState});

  final GameState gameState;

  @override
  State<_ProUpgradeSheet> createState() => _ProUpgradeSheetState();
}

class _ProUpgradeSheetState extends State<_ProUpgradeSheet> {
  late _Phase _phase =
      widget.gameState.isPro ? _Phase.done : _Phase.offer;
  late final bool _alreadyPro = widget.gameState.isPro;

  Future<void> _buy() async {
    setState(() => _phase = _Phase.processing);
    // Pago simulado: una pausa corta para que se sienta como una compra.
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    widget.gameState.upgradeToPro();
    setState(() => _phase = _Phase.done);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: _phase != _Phase.processing,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_phase) {
              _Phase.offer => _Offer(
                  key: const ValueKey('pro-offer'),
                  theme: theme,
                  onBuy: _buy,
                  onClose: () => Navigator.of(context).pop(),
                ),
              _Phase.processing => _Processing(
                  key: const ValueKey('pro-processing'),
                  theme: theme,
                ),
              _Phase.done => _Done(
                  key: const ValueKey('pro-done'),
                  theme: theme,
                  alreadyPro: _alreadyPro,
                  onClose: () => Navigator.of(context).pop(),
                ),
            },
          ),
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

class _Offer extends StatelessWidget {
  const _Offer({
    super.key,
    required this.theme,
    required this.onBuy,
    required this.onClose,
  });

  final ThemeData theme;
  final VoidCallback onBuy;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _Crown()),
        const SizedBox(height: 12),
        Text(
          'Mejorar a Pro',
          textAlign: TextAlign.center,
          style:
              theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          'Pago único · la compra es simulada',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        const _Benefits(),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('pro-buy-button'),
          onPressed: onBuy,
          icon: const Icon(Icons.workspace_premium_rounded),
          label: Text(
            'Mejorar a Pro · ${GameState.proPrice}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.goldDeep,
            foregroundColor: AppColors.goldInk,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('pro-close-button'),
          onPressed: onClose,
          child: const Text('Ahora no'),
        ),
      ],
    );
  }
}

class _Processing extends StatelessWidget {
  const _Processing({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: 18),
          Text(
            'Procesando el pago…',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Es una simulación, no se cobra nada',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Done extends StatelessWidget {
  const _Done({
    super.key,
    required this.theme,
    required this.alreadyPro,
    required this.onClose,
  });

  final ThemeData theme;
  final bool alreadyPro;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: _Crown()),
        const SizedBox(height: 12),
        Text(
          alreadyPro ? 'Tu cuenta es Pro' : '¡Ya sos Pro!',
          textAlign: TextAlign.center,
          style:
              theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          alreadyPro
              ? 'Estos son tus beneficios activos'
              : 'Beneficios desbloqueados',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        const _Benefits(),
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('pro-done-button'),
          onPressed: onClose,
          child: Text(alreadyPro ? 'Cerrar' : '¡A jugar!'),
        ),
      ],
    );
  }
}
