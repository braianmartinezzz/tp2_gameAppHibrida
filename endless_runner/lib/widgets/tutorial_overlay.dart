import 'dart:async';

import 'package:flutter/material.dart';

import '../game/runner_game.dart';
import '../theme/app_theme.dart';

/// Una línea de una tarjeta informativa: ícono de color + texto.
class _InfoItem {
  const _InfoItem(this.icon, this.color, this.text);

  final IconData icon;
  final Color color;
  final String text;
}

/// Un paso del tutorial. Puede ser de gesto (el usuario lo hace de verdad y el
/// paso avanza solo) o informativo (tarjeta con un botón "Siguiente").
class _TutorialStep {
  const _TutorialStep.gesture({
    required RunnerAction this.expected,
    required this.axis,
    required this.direction,
    required this.title,
    required this.subtitle,
  }) : items = const [];

  const _TutorialStep.info({
    required this.title,
    required this.subtitle,
    required this.items,
  })  : expected = null,
        axis = Axis.vertical,
        direction = 0;

  /// Gesto esperado; `null` en los pasos informativos.
  final RunnerAction? expected;

  /// Eje del gesto: vertical (salto/agachada) u horizontal (carriles).
  final Axis axis;

  /// Vertical: -1 = el dedo sube, +1 = baja. Horizontal: -1 = izquierda,
  /// +1 = derecha.
  final int direction;
  final String title;
  final String subtitle;
  final List<_InfoItem> items;

  bool get isInfo => expected == null;
}

const List<_TutorialStep> _steps = [
  _TutorialStep.gesture(
    expected: RunnerAction.jump,
    axis: Axis.vertical,
    direction: -1,
    title: 'Deslizá hacia arriba',
    subtitle: 'para saltar las vallas bajas',
  ),
  _TutorialStep.gesture(
    expected: RunnerAction.roll,
    axis: Axis.vertical,
    direction: 1,
    title: 'Deslizá hacia abajo',
    subtitle: 'para pasar por debajo de las losas colgantes',
  ),
  _TutorialStep.gesture(
    expected: RunnerAction.moveLeft,
    axis: Axis.horizontal,
    direction: -1,
    title: 'Deslizá a la izquierda',
    subtitle: 'para cambiar de carril',
  ),
  _TutorialStep.gesture(
    expected: RunnerAction.moveRight,
    axis: Axis.horizontal,
    direction: 1,
    title: 'Deslizá a la derecha',
    subtitle: 'hay tres carriles: izquierda, centro y derecha',
  ),
  _TutorialStep.info(
    title: 'Diamantes y corazones',
    subtitle: 'Lo que juntás y lo que cuidás',
    items: [
      _InfoItem(Icons.diamond_rounded, AppColors.gem,
          'Juntá diamantes: se gastan en la tienda'),
      _InfoItem(Icons.favorite_rounded, Color(0xFFFF5C7A),
          'Cada choque te saca un corazón; sin corazones, se termina'),
    ],
  ),
  _TutorialStep.info(
    title: 'Power-ups',
    subtitle: 'Se agarran con solo pasar por encima',
    items: [
      _InfoItem(Icons.shield_rounded, Color(0xFF5AA9FF),
          'Escudo: absorbe un golpe'),
      _InfoItem(Icons.compass_calibration_rounded, Color(0xFFFF6B6B),
          'Imán: atrae los diamantes cercanos'),
      _InfoItem(Icons.bolt_rounded, Color(0xFFFFD166),
          'Multiplicador: el puntaje vale el doble un rato'),
    ],
  ),
  _TutorialStep.info(
    title: 'Cuidado con el camino',
    subtitle: 'Cada obstáculo pide algo distinto',
    items: [
      _InfoItem(Icons.keyboard_double_arrow_up_rounded, AppColors.play,
          'Vallas bajas: saltá'),
      _InfoItem(Icons.keyboard_double_arrow_down_rounded, AppColors.pause,
          'Losas colgantes: agachate'),
      _InfoItem(Icons.swap_horiz_rounded, AppColors.gem,
          'Contenedores y autos (ocupan dos carriles): cambiá de carril'),
      _InfoItem(Icons.warning_amber_rounded, Color(0xFFFF8A65),
          'Los zombis se mueven, y una horda te persigue: no te frenes'),
    ],
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

  /// Botón "Siguiente" de los pasos informativos.
  void _nextInfo() {
    if (_allDone || !_steps[_index].isInfo) return;
    _advance();
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
    final showHand = !_stepDone && !_allDone && !step.isInfo;
    final showInfo = step.isInfo && !_allDone;

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
                    const Color(0xFF0A0706).withValues(alpha: 0.6),
                    const Color(0xFF0A0706).withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!showInfo)
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
                  axis: step.axis,
                  direction: step.direction,
                ),
              ),
            ),
          ),
        if (showInfo)
          Positioned.fill(
            child: Align(
              alignment: const Alignment(0, 0.25),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: _InfoCard(
                  key: ValueKey('info-$_index'),
                  step: step,
                  isLast: _index == _steps.length - 1,
                  onNext: _nextInfo,
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
                backgroundColor: const Color(0xFF140E0C).withValues(alpha: 0.55),
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
        color: const Color(0xFF140E0C).withValues(alpha: 0.82),
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

/// Tarjeta informativa (diamantes, power-ups, peligros) con su botón.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    super.key,
    required this.step,
    required this.isLast,
    required this.onNext,
  });

  final _TutorialStep step;
  final bool isLast;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF140E0C).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: AppColors.gem.withValues(alpha: 0.8), width: 2),
        boxShadow: [
          BoxShadow(
            color: AppColors.gem.withValues(alpha: 0.3),
            blurRadius: 18,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            step.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in step.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: item.color.withValues(alpha: 0.9), width: 1.5),
                    ),
                    child: Icon(item.icon, color: item.color, size: 19),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          FilledButton(
            key: const ValueKey('tutorial-next'),
            onPressed: onNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.play,
              foregroundColor: Colors.white,
            ),
            child: Text(isLast ? '¡Entendido!' : 'Siguiente'),
          ),
        ],
      ),
    );
  }
}

/// Dedo animado que recorre una guía (vertical u horizontal) en la dirección
/// del gesto.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint({
    required this.animation,
    required this.axis,
    required this.direction,
  });

  final Animation<double> animation;
  final Axis axis;

  /// Vertical: -1 sube, +1 baja. Horizontal: -1 izquierda, +1 derecha.
  final int direction;

  static const double _track = 120;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return SizedBox(
      width: horizontal ? _track + 60 : 80,
      height: horizontal ? 80 : _track + 60,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final v = animation.value;
          final t = Curves.easeInOut.transform(v);
          // Aparece en el primer tramo y se desvanece al final del recorrido.
          final opacity = v < 0.15 ? v / 0.15 : (v > 0.8 ? (1 - v) / 0.2 : 1.0);
          final d = direction * (t * _track - _track / 2);
          final arrow = horizontal
              ? (direction < 0
                  ? Icons.keyboard_arrow_left_rounded
                  : Icons.keyboard_arrow_right_rounded)
              : (direction < 0
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded);
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: horizontal ? _track : 6,
                height: horizontal ? 6 : _track,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withValues(alpha: 0.28),
                ),
              ),
              Positioned(
                top: !horizontal && direction < 0 ? 0 : null,
                bottom: !horizontal && direction > 0 ? 0 : null,
                left: horizontal && direction < 0 ? 0 : null,
                right: horizontal && direction > 0 ? 0 : null,
                child: Icon(
                  arrow,
                  size: 34,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              Transform.translate(
                offset: horizontal ? Offset(d, 0) : Offset(0, d),
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
                      color: Color(0xFF181210),
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
