import 'package:flutter/material.dart';

import '../state/game_state.dart';
import '../state/rewards.dart';
import '../theme/app_theme.dart';
import 'ad_modal.dart';

/// Pantalla de premios: desafíos diarios, hitos de puntaje y anuncio
/// voluntario. Todo se ve y se cobra acá; la partida queda pausada debajo.
Future<void> showRewardsModal(BuildContext context, GameState gameState) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
        child: _RewardsContent(gameState: gameState),
      ),
    ),
  );
}

class _RewardsContent extends StatefulWidget {
  const _RewardsContent({required this.gameState});

  final GameState gameState;

  @override
  State<_RewardsContent> createState() => _RewardsContentState();
}

class _RewardsContentState extends State<_RewardsContent> {
  /// Lo ganado en el último anuncio, para mostrarlo en la tarjeta.
  int? _lastAdReward;

  GameState get state => widget.gameState;

  Future<void> _watchAd() async {
    final watched = await showAdModal(context, rewarded: true);
    if (!mounted || !watched) return;
    final amount = state.grantAdReward();
    setState(() => _lastAdReward = amount);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([state.rewardsTick, state.diamonds]),
      builder: (context, _) {
        final challenges = state.challenges;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.card_giftcard_rounded,
                    color: AppColors.goldDeep, size: 30),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Premios',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                _Reward(amount: state.diamonds.value, plus: false),
              ],
            ),
            const SizedBox(height: 16),
            _SectionTitle(
              'Desafíos de hoy',
              trailing: 'Se renuevan a medianoche',
            ),
            for (final c in challenges) ...[
              _ChallengeTile(
                def: c,
                progress: state.challengeProgress(c),
                complete: state.isChallengeComplete(c),
                claimed: state.isChallengeClaimed(c),
                onClaim: () => state.claimChallenge(c),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 10),
            const _SectionTitle('Hitos de puntaje', trailing: 'Una sola vez'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in kMilestones)
                  _MilestoneChip(
                    milestone: m,
                    claimed: state.claimedMilestones.contains(m.score),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _AdCard(
              adsLeft: state.adsLeftToday,
              lastReward: _lastAdReward,
              onWatch: _watchAd,
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.trailing});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          if (trailing != null)
            Text(
              trailing!,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

/// Cantidad de diamantes con su ícono: "+15 💎" o el saldo.
class _Reward extends StatelessWidget {
  const _Reward({required this.amount, this.plus = true});

  final int amount;
  final bool plus;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.diamond_rounded, size: 18, color: AppColors.gem),
        const SizedBox(width: 4),
        Text(
          plus ? '+$amount' : '$amount',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
      ],
    );
  }
}

class _ChallengeTile extends StatelessWidget {
  const _ChallengeTile({
    required this.def,
    required this.progress,
    required this.complete,
    required this.claimed,
    required this.onClaim,
  });

  final ChallengeDef def;
  final int progress;
  final bool complete;
  final bool claimed;
  final VoidCallback onClaim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = def.target == 0 ? 1.0 : progress / def.target;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: claimed ? 0.5 : 1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: complete && !claimed
              ? AppColors.goldDeep
              : theme.colorScheme.outlineVariant,
          width: complete && !claimed ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  def.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: claimed ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      backgroundColor: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                      color: complete ? AppColors.play : AppColors.gem,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$progress / ${def.target}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 92,
            child: claimed
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.play, size: 20),
                      SizedBox(width: 4),
                      Text('Cobrado',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  )
                : complete
                    ? FilledButton(
                        onPressed: onClaim,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.goldDeep,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text('Reclamar +${def.reward}'),
                      )
                    : Center(child: _Reward(amount: def.reward)),
          ),
        ],
      ),
    );
  }
}

class _MilestoneChip extends StatelessWidget {
  const _MilestoneChip({required this.milestone, required this.claimed});

  final ScoreMilestone milestone;
  final bool claimed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: claimed
            ? AppColors.play.withValues(alpha: 0.16)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: claimed ? AppColors.play : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            claimed ? Icons.check_circle_rounded : Icons.flag_rounded,
            size: 16,
            color: claimed
                ? AppColors.play
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            '${milestone.score} pts',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          _Reward(amount: milestone.reward),
        ],
      ),
    );
  }
}

class _AdCard extends StatelessWidget {
  const _AdCard({
    required this.adsLeft,
    required this.lastReward,
    required this.onWatch,
  });

  final int adsLeft;
  final int? lastReward;
  final VoidCallback onWatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canWatch = adsLeft > 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppColors.gem.withValues(alpha: 0.22),
            AppColors.gem.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: AppColors.gem.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.ondemand_video_rounded, color: AppColors.gem),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ganá diamantes mirando un anuncio',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Entre 5 y 20 diamantes por anuncio · '
            '${canWatch ? 'te quedan $adsLeft hoy' : 'volvé mañana'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: lastReward != null && lastReward! > 0
                ? Padding(
                    key: ValueKey(lastReward),
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      '¡Ganaste +$lastReward diamantes!',
                      style: const TextStyle(
                        color: AppColors.play,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: canWatch ? onWatch : null,
              icon: const Icon(Icons.play_circle_rounded),
              label: const Text('Ver anuncio'),
            ),
          ),
        ],
      ),
    );
  }
}
