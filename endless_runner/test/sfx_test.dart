import 'package:flutter_test/flutter_test.dart';
import 'package:runner_flutter/audio/game_sfx.dart';
import 'package:runner_flutter/state/game_state.dart';

void main() {
  tearDown(() => GameSfx.instance.enabled = true);

  test('el interruptor de efectos del GameState llega a GameSfx', () {
    final state = GameState();
    expect(state.sfxEnabled.value, isTrue);

    state.setSfxEnabled(false);
    expect(GameSfx.instance.enabled, isFalse);

    state.setSfxEnabled(true);
    expect(GameSfx.instance.enabled, isTrue);
  });

  test('el ajuste de efectos se guarda en el JSON y vuelve a prender al resetear',
      () {
    final state = GameState()..setSfxEnabled(false);
    expect(state.toJson()['sfx'], isFalse);

    state.resetToFactory();
    expect(state.sfxEnabled.value, isTrue);
    expect(GameSfx.instance.enabled, isTrue);
  });

  test('sfxTap respeta los botones deshabilitados y llama al callback', () {
    expect(sfxTap(null), isNull);

    var taps = 0;
    sfxTap(() => taps++)!();
    expect(taps, 1);
  });

  test('cada efecto apunta a un .wav con volumen válido', () {
    for (final cue in Sfx.values) {
      expect(cue.path, startsWith('sfx/'));
      expect(cue.path, endsWith('.wav'));
      expect(cue.volume, inInclusiveRange(0.0, 1.0));
      expect(cue.voices, greaterThan(0));
    }
  });

  test('los movimientos del corredor suenan más bajo que los botones', () {
    for (final move in [Sfx.stepA, Sfx.stepB, Sfx.lane, Sfx.jump, Sfx.land, Sfx.roll]) {
      expect(move.volume, lessThan(Sfx.click.volume));
    }
  });
}
