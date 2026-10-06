import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../audio/game_sfx.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
import '../theme/app_theme.dart';

/// Overlay de pausa: fondo semitransparente con desenfoque, tarjeta con las
/// acciones y el ajuste de sensibilidad de los gestos.
///
/// "Continuar" no reanuda de golpe: hace una cuenta regresiva 3-2-1 para que el
/// jugador vuelva a poner el dedo antes de que el mundo se mueva.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({
    super.key,
    required this.gameState,
    required this.onResume,
    required this.onRestart,
    required this.onShowTutorial,
    this.onMenu,
  });

  final GameState gameState;

  /// Reanudar (se llama al terminar la cuenta regresiva).
  final VoidCallback onResume;

  /// Reiniciar la partida (la pantalla decide si pasa por el anuncio).
  final VoidCallback onRestart;

  /// Volver a ver el tutorial.
  final VoidCallback onShowTutorial;

  /// Volver al menú principal (si es null, el botón no se muestra).
  final VoidCallback? onMenu;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay> {
  static const Duration _tick = Duration(milliseconds: 700);

  int? _count; // null = menú de pausa; 3, 2, 1 = cuenta regresiva
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    if (_count != null) return;
    setState(() => _count = 3);
    _timer = Timer.periodic(_tick, (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_count! <= 1) {
        timer.cancel();
        widget.onResume();
      } else {
        setState(() => _count = _count! - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Capa semitransparente + desenfoque del juego congelado.
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Container(
              color: const Color(0xFF0A0706).withValues(alpha: 0.58),
            ),
          ),
        ),
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
                child: child,
              ),
            ),
            child: _count == null
                ? _PauseCard(
                    key: const ValueKey('menu'),
                    gameState: widget.gameState,
                    onResume: _startCountdown,
                    onRestart: widget.onRestart,
                    onShowTutorial: widget.onShowTutorial,
                    onMenu: widget.onMenu,
                  )
                : _Countdown(key: ValueKey('count-$_count'), value: _count!),
          ),
        ),
      ],
    );
  }
}

/// Número grande de la cuenta regresiva, con un pequeño "pop" en cada cambio.
class _Countdown extends StatelessWidget {
  const _Countdown({super.key, required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1.5, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutBack,
      builder: (_, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Text(
        '$value',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 96,
          fontWeight: FontWeight.w900,
          shadows: [Shadow(color: Colors.black54, blurRadius: 24)],
        ),
      ),
    );
  }
}

class _PauseCard extends StatelessWidget {
  const _PauseCard({
    super.key,
    required this.gameState,
    required this.onResume,
    required this.onRestart,
    required this.onShowTutorial,
    this.onMenu,
  });

  final GameState gameState;
  final VoidCallback onResume;
  final VoidCallback onRestart;
  final VoidCallback onShowTutorial;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 12),
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
            const _Header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SensitivityControl(gameState: gameState),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Continuar'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: sfxTap(onRestart),
                          icon: const Icon(Icons.replay_rounded, size: 18),
                          label: const Text('Reiniciar'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: sfxTap(onShowTutorial),
                          icon: const Icon(Icons.school_rounded, size: 18),
                          label: const Text('Tutorial'),
                        ),
                      ),
                    ],
                  ),
                  if (onMenu != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: sfxTap(onMenu, sfx: Sfx.back),
                        icon: const Icon(Icons.home_rounded, size: 18),
                        label: const Text('Menú principal'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.pause, AppColors.pauseDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.pause_circle_filled_rounded, color: Colors.white, size: 30),
          SizedBox(width: 10),
          Text(
            'PAUSA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// Slider de sensibilidad de los gestos con el umbral real en píxeles.
class _SensitivityControl extends StatelessWidget {
  const _SensitivityControl({required this.gameState});

  final GameState gameState;

  static String _label(double v) {
    if (v < 0.85) return 'Baja';
    if (v > 1.15) return 'Alta';
    return 'Normal';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<double>(
      valueListenable: gameState.swipeSensitivity,
      builder: (context, value, _) {
        final px = (RunnerGame.baseSwipeThreshold / value).round();
        final isDefault = (value - GameState.defaultSensitivity).abs() < 0.001;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.swipe_rounded,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sensibilidad de los gestos',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: isDefault ? 0 : 1,
                  child: IgnorePointer(
                    ignoring: isDefault,
                    child: TextButton(
                      onPressed: sfxTap(() => gameState
                          .setSwipeSensitivity(GameState.defaultSensitivity)),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('Restablecer'),
                    ),
                  ),
                ),
              ],
            ),
            Slider(
              value: value.clamp(
                GameState.minSensitivity,
                GameState.maxSensitivity,
              ),
              min: GameState.minSensitivity,
              max: GameState.maxSensitivity,
              divisions: 6,
              label: _label(value),
              onChanged: gameState.setSwipeSensitivity,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Menos', style: theme.textTheme.labelSmall),
                // Flexible + padding: el rótulo central (label grande) puede
                // superar el ancho de la tarjeta de pausa; en vez de desbordar
                // por la derecha se corta con puntos y los extremos conservan
                // su separación.
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '${_label(value)} · desliz de $px px',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                Text('Más', style: theme.textTheme.labelSmall),
              ],
            ),
          ],
        );
      },
    );
  }
}
