import 'package:flutter/material.dart';

import '../audio/game_sfx.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'back_arrow.dart';
import 'rewards_modal.dart';

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
    this.onRevive,
    this.onReviveWithDiamonds,
    this.onMenu,
  });

  final GameState gameState;

  /// Revivir (anuncio con premio; gratis para Pro). Si es null, o si ya se
  /// usó en la partida, el botón no aparece.
  final VoidCallback? onRevive;

  /// Revivir pagando [GameState.reviveDiamondCost] diamantes (solo cuenta
  /// basic: la Pro revive gratis). Si es null, el botón no aparece.
  final VoidCallback? onReviveWithDiamonds;

  /// Camino de reinicio. En la app real pasa por el anuncio simulado (mismo
  /// requisito que la botonera externa); en los tests es un contador.
  final VoidCallback onRestart;

  /// Vuelve a la pantalla de inicio (flecha discreta sobre el banner). Si es
  /// null (no se llegó desde el menú) la flecha no aparece.
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final score = gameState.score.value;
    final best = gameState.bestScore.value;
    final newRecord = gameState.isNewRecord.value;
    final runDiamonds = gameState.runDiamonds.value;

    return Container(
      color: const Color(0xFF0A0706).withValues(alpha: 0.62),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        // Entrada: aparece con fundido y un rebote chiquito desde el centro.
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (context, t, child) => Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 340),
            margin: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 30,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    _Banner(newRecord: newRecord),
                    if (onMenu != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: SubtleBackArrow(
                          onPressed: onMenu,
                          color: Colors.white,
                          semanticLabel: 'Volver al menú',
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              label: 'Puntaje',
                              value: '$score',
                              big: true,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatTile(
                              label: 'Récord',
                              value: '$best',
                              color: AppColors.goldDeep,
                            ),
                          ),
                        ],
                      ),
                      if (newRecord) ...[
                        const SizedBox(height: 12),
                        const _RecordBadge(),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.gem.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.diamond_rounded,
                              size: 18,
                              color: AppColors.gemDeep,
                            ),
                            const SizedBox(width: 6),
                            // Flexible: con muchos diamantes el texto no
                            // desborda la pastilla, se corta con puntos.
                            Flexible(
                              child: Text(
                                'Ganaste $runDiamonds diamantes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (onRevive != null && gameState.canRevive) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const ValueKey('revive-button'),
                            onPressed: sfxTap(onRevive),
                            icon: Icon(
                              gameState.isPro
                                  ? Icons.favorite_rounded
                                  : Icons.ondemand_video_rounded,
                            ),
                            label: Text(
                              gameState.isPro
                                  ? 'Revivir gratis (Pro)'
                                  : 'Revivir viendo un anuncio',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.gem,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (onReviveWithDiamonds != null &&
                          gameState.canRevive &&
                          !gameState.isPro) ...[
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            key: const ValueKey('revive-diamonds-button'),
                            onPressed: sfxTap(gameState.canPayRevive
                                ? onReviveWithDiamonds
                                : null),
                            icon: const Icon(Icons.diamond_rounded,
                                color: AppColors.gemDeep),
                            label: Text(
                              'Revivir con ${GameState.reviveDiamondCost} diamantes',
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: sfxTap(onRestart),
                          icon: const Icon(Icons.replay_rounded),
                          label: const Text('Reintentar'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Los premios se cobran acá (no en la botonera, que es
                      // solo para controlar el juego). El número avisa
                      // cuántos hay para cobrar.
                      SizedBox(
                        width: double.infinity,
                        child: ValueListenableBuilder<int>(
                          valueListenable: gameState.claimable,
                          builder: (_, pending, __) => OutlinedButton.icon(
                            key: const ValueKey('rewards-button'),
                            onPressed: () =>
                                showRewardsModal(context, gameState),
                            icon: const Icon(
                              Icons.card_giftcard_rounded,
                              color: AppColors.goldDeep,
                            ),
                            label: Text(
                              pending > 0 ? 'Premios ($pending)' : 'Premios',
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
        ),
      ),
    );
  }
}

/// Cabecera con degradé, trofeo con halo y estrellitas si hubo récord.
class _Banner extends StatelessWidget {
  const _Banner({required this.newRecord});

  final bool newRecord;

  @override
  Widget build(BuildContext context) {
    final colors = newRecord
        ? const [Color(0xFFF08A0C), Color(0xFFC2410C)]
        : const [Color(0xFF5A3A24), Color(0xFF3B2416)];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (newRecord) ...const [
            Positioned(left: 6, top: 4, child: _Sparkle(size: 16)),
            Positioned(left: 40, top: 40, child: _Sparkle(size: 10)),
            Positioned(right: 8, top: 0, child: _Sparkle(size: 20)),
            Positioned(right: 44, top: 44, child: _Sparkle(size: 12)),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.95),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  size: 40,
                  color: newRecord ? AppColors.goldDeep : colors.first,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'PARTIDA TERMINADA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Sparkle extends StatelessWidget {
  const _Sparkle({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(
      Icons.star_rounded,
      size: size,
      color: Colors.white.withValues(alpha: 0.85),
    );
  }
}

/// Medalla "¡NUEVO RÉCORD!" con brillo dorado.
class _RecordBadge extends StatelessWidget {
  const _RecordBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gold, AppColors.goldDeep],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.goldDeep.withValues(alpha: 0.5),
            blurRadius: 14,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome_rounded,
              size: 14, color: AppColors.goldInk),
          const SizedBox(width: 6),
          const Text(
            '¡NUEVO RÉCORD!',
            style: TextStyle(
              color: AppColors.goldInk,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mosaico del resumen: etiqueta arriba, valor grande abajo.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
    this.big = false,
  });

  final String label;
  final String value;
  final Color color;

  /// true para el puntaje final, que se muestra más grande.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: text.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: (big ? text.headlineLarge : text.headlineMedium)?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
