import 'dart:async';

import 'package:flutter/material.dart';

import '../game/runner_game.dart';
import '../theme/app_theme.dart';

/// Un paso del tutorial: qué gesto se espera y cómo se explica.
class _TutorialStep {
  const _TutorialStep({
    required this.expected,
    required this.direction,
    required this.title,
    required this.subtitle,
  });

  final RunnerAction expected;

  /// -1 = el dedo sube, +1 = el dedo baja.
  final int direction;
  final String title;
  final String subtitle;
}

const List<_TutorialStep> _steps = [
  _TutorialStep(
    expected: RunnerAction.jump,
    direction: -1,
    title: 'Deslizá hacia arriba',
    subtitle: 'para saltar los obstáculos bajos',
  ),
  _TutorialStep(
    expected: RunnerAction.roll,
    direction: 1,
    title: 'Deslizá hacia abajo',
    subtitle: 'para pasar por debajo de las barreras altas',
  ),
];

/// Tutorial interactivo de la primera partida.
///
/// Se monta sobre el corredor, que está en modo tutorial (sin obstáculos): el
/// usuario hace el gesto de verdad y ve saltar o deslizarse al personaje. El
/// paso avanza solo cuando el juego informa la acción esperada vía
/// [RunnerGame.onAction].
///
/// Todo el overlay ignora los toques salvo el botón "Saltar": los gestos
/// llegan al juego que está debajo.
class TutorialOverlay extends StatefulWidget {
  const TutorialOverlay({
    super.key,
    required this.game,
    required this.onFinished,
  });

  final RunnerGame game;

  /// Se llama al terminar los pasos o al saltear el tutorial.
  final VoidCallback onFinished;

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hint;
  Timer? _timer;

  int _index = 0;
  bool _stepDone = false; // paso cumplido, mostrando el tilde
  bool _allDone = false; // último paso cumplido, mostrando "¡Listo!"
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _hint = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    widget.game.onAction = _onAction;
  }

  @override
  void dispose() {
    // Solo si sigue siendo nuestro: un tutorial nuevo pudo registrar el suyo
    // mientras este se desvanecía.
    if (widget.game.onAction == _onAction) widget.game.onAction = null;
    _timer?.cancel();
    _hint.dispose();
    super.dispose();
  }

  void _onAction(RunnerAction action) {
    if (_stepDone || _allDone || action != _steps[_index].expected) return;
    setState(() => _stepDone = true);
    _timer = Timer(const Duration(milliseconds: 900), _advance);
  }

  void _advance() {
    if (!mounted) return;
    if (_index + 1 < _steps.length) {
      setState(() {
        _index++;
        _stepDone = false;
      });
    } else {
      setState(() => _allDone = true);
      _timer = Timer(const Duration(milliseconds: 1100), _close);
    }
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_index];
    final showHand = !_stepDone && !_allDone;

    return Stack(
      children: [
        // Velo suave arriba: da contraste al texto sin tapar el corredor.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 190,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF05060F).withValues(alpha: 0.6),
                    const Color(0xFF05060F).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 52,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: _InstructionCard(
                  key: ValueKey('$_index-$_stepDone-$_allDone'),
                  title: _allDone
                      ? '¡Listo, a correr!'
                      : _stepDone
                          ? '¡Bien!'
                          : step.title,
                  subtitle: _allDone
                      ? 'Esquivá, juntá diamantes y batí tu récord'
                      : _stepDone
                          ? 'Así se hace'
                          : step.subtitle,
                  success: _stepDone || _allDone,
                  stepIndex: _index,
                  stepCount: _steps.length,
                ),
              ),
            ),
          ),
        ),
        if (showHand)
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0, 0.3),
                child: _SwipeHint(
                  animation: _hint,
                  direction: step.direction,
                ),
              ),
            ),
          ),
        Positioned(
          top: 10,
          right: 10,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _allDone ? 0 : 1,
            child: TextButton(
              onPressed: _allDone ? null : _close,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: const Color(0xFF0B1224).withValues(alpha: 0.55),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Saltar tutorial'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta con la consigna del paso (o el tilde de éxito) y los puntitos de
/// progreso.
class _InstructionCard extends StatelessWidget {
  const _InstructionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.success,
    required this.stepIndex,
    required this.stepCount,
  });

  final String title;
  final String subtitle;
  final bool success;
  final int stepIndex;
  final int stepCount;

  @override
  Widget build(BuildContext context) {
    final accent = success ? AppColors.play : AppColors.gem;
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1224).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.8), width: 2),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.3),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (success) ...[
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.play, size: 22),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < stepCount; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == stepIndex ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: i < stepIndex || (i == stepIndex && success)
                        ? AppColors.play
                        : Colors.white.withValues(alpha: i == stepIndex ? 0.9 : 0.35),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Dedo animado que recorre una guía vertical en la dirección del gesto.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({required this.animation, required this.direction});

  final Animation<double> animation;

  /// -1 = sube, +1 = baja.
  final int direction;

  static const double _track = 120;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: _track + 60,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final v = animation.value;
          final t = Curves.easeInOut.transform(v);
          // Aparece en el primer tramo y se desvanece al final del recorrido.
          final opacity = v < 0.15 ? v / 0.15 : (v > 0.8 ? (1 - v) / 0.2 : 1.0);
          final dy = direction * (t * _track - _track / 2);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 6,
                height: _track,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withValues(alpha: 0.28),
                ),
              ),
              Positioned(
                top: direction < 0 ? 0 : null,
                bottom: direction > 0 ? 0 : null,
                child: Icon(
                  direction < 0
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 34,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              Transform.translate(
                offset: Offset(0, dy),
                child: Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.92),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.gem.withValues(alpha: 0.6),
                          blurRadius: 18,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.touch_app_rounded,
                      size: 30,
                      color: Color(0xFF14122B),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
