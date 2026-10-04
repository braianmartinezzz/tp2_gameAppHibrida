import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../game/runner_game.dart';
import '../state/game_state.dart';
import '../state/rewards.dart';
import '../theme/app_theme.dart';
import '../widgets/ad_modal.dart';
import '../widgets/game_controls.dart';
import '../widgets/game_header.dart';
import '../widgets/game_over_overlay.dart';
import '../widgets/pause_overlay.dart';
import '../widgets/record_chip.dart';
import '../widgets/tutorial_overlay.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.gameState});

  final GameState gameState;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final RunnerGame _game;

  /// true mientras se muestra el tutorial (primera vez o "Tutorial" del menú
  /// de pausa).
  final ValueNotifier<bool> _tutorialVisible = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _game = RunnerGame(gameState: widget.gameState);
    // Primera vez: el corredor arranca en modo tutorial (sin obstáculos).
    if (!widget.gameState.tutorialSeen.value) {
      _game.tutorialActive = true;
      _tutorialVisible.value = true;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tutorialVisible.dispose();
    super.dispose();
  }

  /// Si la app pierde el foco en plena partida (llamada, notificación, otra
  /// app) se pausa con el overlay visible: al volver nadie muere de sorpresa.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _game.pauseGame();
      widget.gameState.save(); // por si la pausa no aplicaba (game over)
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = widget.gameState;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Entrada de la pantalla: el header baja y la botonera sube
            // mientras el marco del juego aparece con un fundido.
            _Entrance(
              from: const Offset(0, -24),
              child: GameHeader(
                gameState: state,
                onBeforeShop: _game.pauseGame,
              ),
            ),
            Expanded(
              child: _Entrance(
                from: Offset.zero,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
                  // Marco con degradé y brillo: el corredor queda "enmarcado"
                  // como una pantallita de arcade.
                  child: Container(
                    padding: const EdgeInsets.all(3.5),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      gradient: LinearGradient(
                        colors: [scheme.primary, AppColors.gem, scheme.tertiary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22.5),
                      // El corredor y sus capas de interfaz (récord, pausa,
                      // tutorial y resumen) comparten la misma área: los
                      // widgets van encima del juego, sin tocar el header ni
                      // la botonera.
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          GameWidget(game: _game),
                          // Récord y diamantes de la corrida, arriba a la
                          // izquierda (el HUD de power-ups ocupa la derecha,
                          // en el canvas).
                          Positioned(
                            top: 10,
                            left: 10,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: state.isGameOver,
                              builder: (_, over, __) => over
                                  ? const SizedBox.shrink()
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        RecordChip(gameState: state),
                                        const SizedBox(height: 6),
                                        _LivesChip(gameState: state),
                                        const SizedBox(height: 6),
                                        _RunDiamondsChip(gameState: state),
                                      ],
                                    ),
                            ),
                          ),
                          // Botón de pausa flotante, arriba al centro.
                          Positioned(
                            top: 10,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _PauseButton(
                                game: _game,
                                gameState: state,
                                tutorialVisible: _tutorialVisible,
                              ),
                            ),
                          ),
                          // Cartelito de premios (hitos, desafíos cumplidos).
                          Positioned(
                            top: 62,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: _RewardToast(gameState: state),
                            ),
                          ),
                          // Tutorial de la primera vez: deja pasar los gestos
                          // al juego (ver TutorialOverlay).
                          Positioned.fill(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _tutorialVisible,
                              builder: (_, show, __) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: show
                                    ? TutorialOverlay(
                                        key: const ValueKey('tutorial'),
                                        game: _game,
                                        onFinished: _finishTutorial,
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('no-tutorial'),
                                      ),
                              ),
                            ),
                          ),
                          // Pausa: velo semitransparente con el menú.
                          Positioned.fill(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: state.isPaused,
                              builder: (_, paused, __) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: paused
                                    ? PauseOverlay(
                                        key: const ValueKey('paused'),
                                        gameState: state,
                                        onResume: _game.resumeGame,
                                        onRestart: _restartAfterAd,
                                        onShowTutorial: _replayTutorial,
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('running'),
                                      ),
                              ),
                            ),
                          ),
                          // Resumen al morir: queda por encima de todo.
                          Positioned.fill(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: state.isGameOver,
                              builder: (_, over, __) => AnimatedSwitcher(
                                duration: const Duration(milliseconds: 220),
                                child: over
                                    ? GameOverOverlay(
                                        key: const ValueKey('over'),
                                        gameState: state,
                                        onRestart: _restartAfterAd,
                                        onRevive: _reviveWithAd,
                                      )
                                    : const SizedBox.shrink(
                                        key: ValueKey('alive'),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _Entrance(
              from: const Offset(0, 24),
              child: GameControls(game: _game, gameState: state),
            ),
          ],
        ),
      ),
    );
  }

  /// Fin (o salteo) del tutorial: se recuerda que ya se vio y arranca una
  /// partida limpia.
  void _finishTutorial() {
    widget.gameState.markTutorialSeen();
    _game.tutorialActive = false;
    _tutorialVisible.value = false;
    _game.restartRun();
  }

  /// "Tutorial" del menú de pausa: vuelve a practicar sin obstáculos.
  void _replayTutorial() {
    _game.restartRun(); // limpia la corrida y quita la pausa
    _game.tutorialActive = true;
    _tutorialVisible.value = true;
  }

  /// Reintento desde el resumen o desde la pausa: mismo camino que la
  /// botonera externa (anuncio simulado y después reinicio, requisito de la
  /// consigna).
  Future<void> _restartAfterAd() async {
    await showInterstitialAd(context, widget.gameState);
    if (!mounted) return;
    _game.restartRun();
  }

  bool _reviving = false;

  /// "Revivir" desde el resumen: anuncio con premio (hay que verlo completo) y
  /// la misma partida sigue con una vida. La cuenta Pro revive sin anuncio.
  /// Una sola vez por partida (lo controla [GameState.canRevive]).
  Future<void> _reviveWithAd() async {
    final state = widget.gameState;
    if (_reviving || !state.canRevive) return;
    _reviving = true;
    try {
      if (!state.isPro) {
        final watched = await showAdModal(
          context,
          hint: 'Mirá el anuncio completo para seguir jugando',
          closeLabel: 'Revivir',
        );
        if (!watched || !mounted) return;
      }
      _game.reviveRun();
    } finally {
      _reviving = false;
    }
  }
}

/// Corazones de la partida: llenos los que quedan, vacíos los perdidos. Al
/// perder uno, el ícono "salta" con un cambio animado.
class _LivesChip extends StatelessWidget {
  const _LivesChip({required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: gameState.lives,
      builder: (_, lives, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1224).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < GameState.maxLives; i++)
              Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: i < lives
                      ? const Icon(
                          Icons.favorite_rounded,
                          key: ValueKey('full'),
                          color: Color(0xFFFF5C7A),
                          size: 20,
                        )
                      : Icon(
                          Icons.favorite_border_rounded,
                          key: const ValueKey('empty'),
                          color: Colors.white.withValues(alpha: 0.45),
                          size: 20,
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Cartelito que aparece un rato arriba del corredor cuando se cobra un hito
/// o se cumple un desafío. Se anima solo (entra, se queda, se va) y no usa
/// temporizadores.
class _RewardToast extends StatelessWidget {
  const _RewardToast({required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RewardEvent?>(
      valueListenable: gameState.rewardEvent,
      builder: (_, event, __) {
        if (event == null) return const SizedBox.shrink();
        return Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(event.id),
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 2800),
            builder: (_, t, child) {
              // Entra en el primer 10 %, se queda, y se apaga en el último 20 %.
              final opacity =
                  t < 0.1 ? t / 0.1 : (t > 0.8 ? (1 - t) / 0.2 : 1.0);
              final dy = t < 0.1 ? -12 * (1 - t / 0.1) : 0.0;
              return Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Transform.translate(offset: Offset(0, dy), child: child),
              );
            },
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFF0B1224).withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.gold, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.emoji_events_rounded,
                      color: AppColors.gold, size: 22),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      event.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (event.diamonds > 0) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.diamond_rounded,
                        color: AppColors.gem, size: 16),
                    const SizedBox(width: 2),
                    Text(
                      '+${event.diamonds}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Entrada suave de un bloque de la pantalla: fundido + desplazamiento corto.
class _Entrance extends StatelessWidget {
  const _Entrance({required this.from, required this.child});

  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (_, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(from.dx * (1 - t), from.dy * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Botón redondo de pausa sobre el corredor. Se desvanece (y deja de recibir
/// toques) cuando no se puede pausar: pausa activa, partida terminada o
/// tutorial.
class _PauseButton extends StatelessWidget {
  const _PauseButton({
    required this.game,
    required this.gameState,
    required this.tutorialVisible,
  });

  final RunnerGame game;
  final GameState gameState;
  final ValueListenable<bool> tutorialVisible;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        gameState.isGameOver,
        gameState.isPaused,
        tutorialVisible,
      ]),
      builder: (context, _) {
        final visible = !gameState.isGameOver.value &&
            !gameState.isPaused.value &&
            !tutorialVisible.value;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1 : 0,
          child: IgnorePointer(
            ignoring: !visible,
            child: Tooltip(
              message: 'Pausar',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: game.pauseGame,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0B1224).withValues(alpha: 0.55),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                  child: const Icon(
                    Icons.pause_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Diamantes ganados en la corrida actual ("+N"), sobre el corredor.
class _RunDiamondsChip extends StatelessWidget {
  const _RunDiamondsChip({required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 11, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1224).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.diamond_rounded, size: 15, color: AppColors.gem),
          const SizedBox(width: 5),
          ValueListenableBuilder<int>(
            valueListenable: gameState.runDiamonds,
            builder: (_, runDiamonds, __) => Text(
              '+$runDiamonds',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
