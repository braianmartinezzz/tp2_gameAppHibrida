import 'package:flutter/material.dart';

import '../game/runner_game.dart';
import '../state/game_state.dart';
import 'pixel_ui.dart';

/// Abre el diálogo de ajustes del menú principal.
Future<void> showSettingsDialog(BuildContext context, GameState gameState) =>
    showPixelDialog(
      context,
      title: 'AJUSTES',
      body: SettingsContent(gameState: gameState),
    );

/// Pide confirmación y, si el usuario acepta, restablece la app de fábrica.
/// Cierra también el diálogo de Ajustes y avisa con un cartelito.
Future<void> _confirmFactoryReset(
  BuildContext settingsContext,
  GameState gameState,
) {
  final navigator = Navigator.of(settingsContext);
  final messenger = ScaffoldMessenger.maybeOf(settingsContext);
  return showPixelDialog(
    settingsContext,
    title: 'RESTABLECER',
    body: _FactoryResetConfirm(
      onConfirm: () {
        gameState.resetToFactory();
        navigator.pop(); // cierra Ajustes (la confirmación ya se cerró sola)
        messenger?.showSnackBar(
          const SnackBar(content: Text('Listo: la app volvió a estado de fábrica')),
        );
      },
    ),
  );
}

class _FactoryResetConfirm extends StatelessWidget {
  const _FactoryResetConfirm({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '¿Borrar todo?',
          style: PixelStyle.text(11, color: PixelStyle.cream),
        ),
        const SizedBox(height: 10),
        Text(
          'Se pierden los diamantes, las mejoras, el récord, los logros y los '
          'ajustes. La cuenta vuelve a BASIC y el tutorial se muestra de nuevo. '
          'No se puede deshacer.',
          style: PixelStyle.text(8, color: PixelStyle.creamDim, height: 1.7),
        ),
        const SizedBox(height: 18),
        PixelButton(
          semanticLabel: 'Confirmar restablecer de fábrica',
          pixel: 2,
          padding: const EdgeInsets.symmetric(vertical: 12),
          fill: const [PixelStyle.alert, Color(0xFF8E2323)],
          border: PixelStyle.ink,
          onTap: () {
            Navigator.of(context).pop(); // cierra la confirmación
            onConfirm();
          },
          child: Center(
            child: Text('SÍ, BORRAR TODO', style: PixelStyle.text(9)),
          ),
        ),
        const SizedBox(height: 10),
        PixelButton(
          semanticLabel: 'Cancelar',
          pixel: 2,
          padding: const EdgeInsets.symmetric(vertical: 12),
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Text('CANCELAR', style: PixelStyle.text(9)),
          ),
        ),
      ],
    );
  }
}

/// Abre el diálogo con el mejor puntaje.
Future<void> showRecordDialog(BuildContext context, GameState gameState) =>
    showPixelDialog(
      context,
      title: 'RÉCORD',
      body: RecordContent(gameState: gameState),
    );

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: PixelStyle.text(10, color: PixelStyle.creamDim)),
      );
}

/// Sensibilidad de los gestos, tema (día/noche del desierto) y tutorial: los
/// mismos ajustes del menú de pausa, accesibles antes de empezar a jugar.
class SettingsContent extends StatelessWidget {
  const SettingsContent({super.key, required this.gameState});

  final GameState gameState;

  static String _sensLabel(double v) {
    if (v < 0.85) return 'BAJA';
    if (v > 1.15) return 'ALTA';
    return 'NORMAL';
  }

  @override
  Widget build(BuildContext context) {
    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 6,
      activeTrackColor: PixelStyle.plankTop,
      inactiveTrackColor: PixelStyle.panelEdge,
      thumbColor: PixelStyle.plankTop,
      overlayColor: PixelStyle.plankTop.withValues(alpha: 0.2),
      valueIndicatorColor: PixelStyle.plankTop,
      valueIndicatorTextStyle: PixelStyle.text(9, color: PixelStyle.plankInk),
      activeTickMarkColor: PixelStyle.ink,
      inactiveTickMarkColor: PixelStyle.ink,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _Label('SENSIBILIDAD'),
        ValueListenableBuilder<double>(
          valueListenable: gameState.swipeSensitivity,
          builder: (_, value, __) {
            final px = (RunnerGame.baseSwipeThreshold / value).round();
            return Column(
              children: [
                SliderTheme(
                  data: sliderTheme,
                  child: Slider(
                    value: value.clamp(
                      GameState.minSensitivity,
                      GameState.maxSensitivity,
                    ),
                    min: GameState.minSensitivity,
                    max: GameState.maxSensitivity,
                    divisions: 6,
                    label: _sensLabel(value),
                    onChanged: gameState.setSwipeSensitivity,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('MENOS', style: PixelStyle.text(8, color: PixelStyle.creamDim)),
                    Text('${_sensLabel(value)} · $px PX', style: PixelStyle.text(8)),
                    Text('MÁS', style: PixelStyle.text(8, color: PixelStyle.creamDim)),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const _Label('TEMA'),
        ValueListenableBuilder<ThemeMode>(
          valueListenable: gameState.themeMode,
          builder: (_, mode, __) => Row(
            children: [
              for (final (m, label) in const [
                (ThemeMode.system, 'AUTO'),
                (ThemeMode.light, 'DÍA'),
                (ThemeMode.dark, 'NOCHE'),
              ])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: m == ThemeMode.dark ? 0 : 8),
                    child: PixelButton(
                      semanticLabel: 'Tema $label',
                      pixel: 2,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      fill: m == mode
                          ? const [PixelStyle.plankTop, PixelStyle.plankBottom]
                          : const [PixelStyle.panel, PixelStyle.panelDeep],
                      border: m == mode ? PixelStyle.plankBorder : PixelStyle.ink,
                      onTap: () {
                        gameState.themeMode.value = m;
                        gameState.save();
                      },
                      child: Center(
                        child: Text(
                          label,
                          style: PixelStyle.text(
                            9,
                            color: m == mode
                                ? PixelStyle.plankInk
                                : PixelStyle.cream,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'El desierto cambia de día a noche.',
          style: PixelStyle.text(8, color: PixelStyle.creamDim, height: 1.6),
        ),
        const SizedBox(height: 20),
        const _Label('MÚSICA'),
        ValueListenableBuilder<bool>(
          valueListenable: gameState.musicEnabled,
          builder: (_, enabled, __) => Row(
            children: [
              for (final (value, label) in const [
                (true, 'SÍ'),
                (false, 'NO'),
              ])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: value ? 8 : 0),
                    child: PixelButton(
                      semanticLabel: 'Música $label',
                      pixel: 2,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      fill: enabled == value
                          ? const [PixelStyle.plankTop, PixelStyle.plankBottom]
                          : const [PixelStyle.panel, PixelStyle.panelDeep],
                      border: enabled == value
                          ? PixelStyle.plankBorder
                          : PixelStyle.ink,
                      onTap: () => gameState.setMusicEnabled(value),
                      child: Center(
                        child: Text(
                          label,
                          style: PixelStyle.text(
                            9,
                            color: enabled == value
                                ? PixelStyle.plankInk
                                : PixelStyle.cream,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'La canción de la partida empieza cuando el corredor sale a correr.',
          style: PixelStyle.text(8, color: PixelStyle.creamDim, height: 1.6),
        ),
        const SizedBox(height: 20),
        const _Label('VIBRACIÓN'),
        ValueListenableBuilder<bool>(
          valueListenable: gameState.hapticsEnabled,
          builder: (_, enabled, __) => Row(
            children: [
              for (final (value, label) in const [
                (true, 'SÍ'),
                (false, 'NO'),
              ])
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: value ? 8 : 0),
                    child: PixelButton(
                      semanticLabel: 'Vibración $label',
                      pixel: 2,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      fill: enabled == value
                          ? const [PixelStyle.plankTop, PixelStyle.plankBottom]
                          : const [PixelStyle.panel, PixelStyle.panelDeep],
                      border: enabled == value
                          ? PixelStyle.plankBorder
                          : PixelStyle.ink,
                      onTap: () => gameState.setHapticsEnabled(value),
                      child: Center(
                        child: Text(
                          label,
                          style: PixelStyle.text(
                            9,
                            color: enabled == value
                                ? PixelStyle.plankInk
                                : PixelStyle.cream,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'El teléfono vibra al chocar contra un obstáculo o un zombi.',
          style: PixelStyle.text(8, color: PixelStyle.creamDim, height: 1.6),
        ),
        const SizedBox(height: 20),
        const _Label('TUTORIAL'),
        ValueListenableBuilder<bool>(
          valueListenable: gameState.tutorialSeen,
          builder: (_, seen, __) => seen
              ? PixelButton(
                  semanticLabel: 'Ver el tutorial otra vez',
                  pixel: 2,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  onTap: () {
                    gameState.tutorialSeen.value = false;
                    gameState.save();
                  },
                  child: Center(
                    child: Text('VER OTRA VEZ', style: PixelStyle.text(9)),
                  ),
                )
              : Text(
                  'Se mostrará al empezar a jugar.',
                  style: PixelStyle.text(8, color: PixelStyle.plankTop, height: 1.6),
                ),
        ),
        const SizedBox(height: 20),
        const _Label('DATOS'),
        PixelButton(
          semanticLabel: 'Restablecer de fábrica',
          pixel: 2,
          padding: const EdgeInsets.symmetric(vertical: 12),
          fill: const [PixelStyle.alert, Color(0xFF8E2323)],
          border: PixelStyle.ink,
          onTap: () => _confirmFactoryReset(context, gameState),
          child: Center(
            child: Text('RESTABLECER DE FÁBRICA', style: PixelStyle.text(9)),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Vuelve todo como recién instalada: diamantes, cuenta, mejoras y ajustes.',
          style: PixelStyle.text(8, color: PixelStyle.creamDim, height: 1.6),
        ),
      ],
    );
  }
}

/// Mejor puntaje de la sesión y diamantes.
class RecordContent extends StatelessWidget {
  const RecordContent({super.key, required this.gameState});

  final GameState gameState;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('PUNTAJE MÁXIMO', style: PixelStyle.text(10, color: PixelStyle.creamDim)),
        const SizedBox(height: 14),
        ValueListenableBuilder<int>(
          valueListenable: gameState.bestScore,
          builder: (_, best, __) => Column(
            children: [
              Text(
                '$best',
                style: PixelStyle.text(
                  best >= 100000 ? 22 : 32,
                  color: PixelStyle.plankTop,
                  shadows: const [
                    Shadow(color: PixelStyle.plankBorder, offset: Offset(0, 3)),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                best == 0 ? 'Todavía no jugaste.\n¡Salí a correr!' : '¿Podés superarlo?',
                textAlign: TextAlign.center,
                style: PixelStyle.text(8, color: PixelStyle.cream, height: 1.8),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
