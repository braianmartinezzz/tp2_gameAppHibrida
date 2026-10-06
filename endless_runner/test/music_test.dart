import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:runner_flutter/audio/game_music.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/settings_store.dart';

/// Doble de [GameMusic]: no toca el plugin de audio y anota lo que el juego
/// manda hacer, para poder afirmar la política de música sin sonar.
class _FakeMusic extends GameMusic {
  final List<String> calls = [];

  @override
  Future<void> start() async => calls.add('start');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> resume() async => calls.add('resume');

  @override
  Future<void> dispose() async => calls.add('dispose');
}

/// Música de la partida: el interruptor de Ajustes (con su guardado) y el
/// ciclo de vida de la corrida (arrancar, pausar, morir, revivir, reiniciar,
/// volver al menú).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('interruptor de Ajustes', () {
    test('arranca prendida', () {
      expect(GameState().musicEnabled.value, isTrue);
    });

    test('setMusicEnabled avisa a los oyentes y no repite el mismo valor', () {
      final state = GameState();
      var notifications = 0;
      state.musicEnabled.addListener(() => notifications++);

      state.setMusicEnabled(false);
      expect(state.musicEnabled.value, isFalse);
      expect(notifications, 1);

      state.setMusicEnabled(false); // igual que antes: nadie se entera
      expect(notifications, 1);
    });

    test('la música elegida se guarda y se recupera', () async {
      SharedPreferences.setMockInitialValues({});
      final store = SettingsStore();

      final first = GameState(store: store)..setMusicEnabled(false);
      expect(first.toJson()['music'], isFalse);
      await pumpEventQueue();

      final second = GameState(store: store);
      await second.loadSettings();
      expect(second.musicEnabled.value, isFalse);
    });

    test('un guardado viejo sin la clave deja la música prendida', () async {
      SharedPreferences.setMockInitialValues({
        'game_save_v1': '{"tutorialSeen":true,"swipeSensitivity":1.5}',
      });

      final state = GameState(store: SettingsStore());
      await state.loadSettings();

      expect(state.musicEnabled.value, isTrue);
      // El resto del save sí se carga: la clave nueva es opcional.
      expect(state.tutorialSeen.value, isTrue);
      expect(state.swipeSensitivity.value, 1.5);
    });
  });

  group('ciclo de vida en la partida', () {
    testWidgets('la música sigue a la corrida de punta a punta',
        (tester) async {
      final state = GameState();
      final music = _FakeMusic();
      final game = RunnerGame(
        gameState: state,
        music: music,
        hordeEnabled: false,
        zombiesEnabled: false, trucksEnabled: false,
      );

      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));
      // El corredor sale a correr: entra la música.
      expect(music.calls, ['resume']);

      // Pausa y reanuda en el punto donde estaba.
      game.pauseGame();
      expect(music.calls.last, 'pause');
      game.resumeGame();
      expect(music.calls.last, 'resume');

      // Muere: se corta. Revive: sigue la misma partida.
      state.finishRun();
      expect(music.calls.last, 'pause');
      expect(state.revive(), isTrue);
      expect(music.calls.last, 'resume');

      // Partida nueva: el tema vuelve a empezar desde el principio.
      game.restartRun();
      expect(music.calls.last, 'start');

      // Interruptor de Ajustes apagado y prendido en plena corrida.
      state.setMusicEnabled(false);
      expect(music.calls.last, 'pause');
      state.setMusicEnabled(true);
      expect(music.calls.last, 'resume');

      // Volver al menú: se corta y se libera el player.
      await tester.pumpWidget(const SizedBox());
      expect(music.calls.last, 'dispose');
    });

    testWidgets('con la música apagada en Ajustes no arranca al entrar',
        (tester) async {
      final state = GameState()..setMusicEnabled(false);
      final music = _FakeMusic();
      final game = RunnerGame(
        gameState: state,
        music: music,
        hordeEnabled: false,
        zombiesEnabled: false, trucksEnabled: false,
      );

      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 16));

      expect(music.calls, isNot(contains('resume')));
      expect(music.calls, isNot(contains('start')));
    });
  });

  group('sin plugin de audio (tests)', () {
    test('GameMusic no se queja cuando no hay reproducción posible', () async {
      final music = GameMusic();
      // En el entorno de tests la clase queda muda: si en algún momento
      // volviera a tocar el plugin, estos llamados romperían el test.
      await music.start();
      await music.pause();
      await music.resume();
      await music.dispose();
    });
  });
}
