import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/rewards.dart';
import 'package:runner_flutter/state/settings_store.dart';
import 'package:runner_flutter/widgets/menu_dialogs.dart';

class _FakeStore extends SettingsStore {
  Map<String, dynamic>? saved;
  bool cleared = false;

  @override
  Future<Map<String, dynamic>?> load() async => saved;

  @override
  Future<void> save(Map<String, dynamic> data) async => saved = data;

  @override
  Future<void> clear() async {
    cleared = true;
    saved = null;
  }
}

/// Deja el estado "lleno de progreso": todo distinto del valor de fábrica.
GameState _usedState({SettingsStore? store}) {
  final state = GameState(store: store, clock: () => DateTime(2026, 10, 3, 12));
  state
    ..diamonds.value = 999
    ..upgradeToPro()
    ..buyUpgrade(kUpgrades.first)
    ..addScore(1200) // hitos 500 y 1000
    ..grantAdReward()
    ..markTutorialSeen()
    ..setSwipeSensitivity(1.8)
    ..setMusicEnabled(false)
    ..themeMode.value = ThemeMode.dark
    ..finishRun();
  return state;
}

void main() {
  group('resetToFactory', () {
    test('deja todo como una instalación nueva', () {
      final state = _usedState();
      expect(state.isPro, isTrue);
      expect(state.bestScore.value, greaterThan(0));

      state.resetToFactory();

      final fresh = GameState(clock: () => DateTime(2026, 10, 3, 12));
      expect(state.accountType.value, 'basic');
      expect(state.isPro, isFalse);
      expect(state.diamonds.value, fresh.diamonds.value);
      expect(state.diamonds.value, 85);
      expect(state.upgradeLevels.value, isEmpty);
      expect(state.claimedMilestones, isEmpty);
      expect(state.bestScore.value, 0);
      expect(state.score.value, 0);
      expect(state.runDiamonds.value, 0);
      expect(state.isGameOver.value, isFalse);
      expect(state.isPaused.value, isFalse);
      expect(state.isNewRecord.value, isFalse);
      expect(state.canRevive, isFalse);
      expect(state.lives.value, GameState.maxLives);
      expect(state.startingLives, GameState.maxLives);
      expect(state.tutorialSeen.value, isFalse);
      expect(state.musicEnabled.value, isTrue);
      expect(state.swipeSensitivity.value, GameState.defaultSensitivity);
      expect(state.themeMode.value, ThemeMode.system);
      expect(state.username.value, fresh.username.value);
      expect(state.adsLeftToday, GameState.maxAdsPerDay);
      expect(state.claimable.value, 0);
      expect(state.rewardEvent.value, isNull);
      for (final c in state.challenges) {
        expect(state.challengeProgress(c), 0);
        expect(state.isChallengeClaimed(c), isFalse);
      }
    });

    test('borra lo guardado en disco y no lo vuelve a escribir', () async {
      final store = _FakeStore();
      final state = _usedState(store: store);
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, isNotNull);

      state.resetToFactory();
      await Future<void>.delayed(Duration.zero);

      expect(store.cleared, isTrue);
      expect(store.saved, isNull, reason: 'la clave se borra, no se pisa');
    });

    test('al reabrir la app no queda nada del progreso anterior', () async {
      final store = _FakeStore();
      _usedState(store: store).resetToFactory();
      await Future<void>.delayed(Duration.zero);

      final reopened = GameState(store: store);
      await reopened.loadSettings();
      expect(reopened.isPro, isFalse);
      expect(reopened.diamonds.value, 85);
      expect(reopened.tutorialSeen.value, isFalse);
      expect(reopened.upgradeLevels.value, isEmpty);
    });

    test('después de restablecer se puede seguir jugando y comprando', () {
      final state = _usedState()..resetToFactory();
      state.resetRun();
      expect(state.buyUpgrade(kUpgrades.first), isTrue);
      expect(state.diamonds.value, 85 - kUpgrades.first.costs.first);
      expect(state.upgradeToPro(), isTrue);
    });
  });

  group('Ajustes: botón de restablecer', () {
    Future<void> openSettings(WidgetTester tester, GameState state) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSettingsDialog(context, state),
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    Future<void> tapReset(WidgetTester tester) async {
      final button = find.text('RESTABLECER DE FÁBRICA');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('pide confirmación y "Cancelar" no borra nada', (tester) async {
      final state = _usedState();
      await openSettings(tester, state);
      await tapReset(tester);

      expect(find.text('¿Borrar todo?'), findsOneWidget);
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();

      expect(state.isPro, isTrue);
      expect(state.diamonds.value, greaterThan(85));
      expect(find.text('AJUSTES'), findsOneWidget, reason: 'sigue en Ajustes');
    });

    testWidgets('confirmar restablece todo y cierra Ajustes', (tester) async {
      final state = _usedState();
      await openSettings(tester, state);
      await tapReset(tester);

      await tester.tap(find.text('SÍ, BORRAR TODO'));
      await tester.pumpAndSettle();

      expect(state.isPro, isFalse);
      expect(state.diamonds.value, 85);
      expect(state.tutorialSeen.value, isFalse);
      expect(state.themeMode.value, ThemeMode.system);
      expect(find.text('AJUSTES'), findsNothing);
      expect(find.text('RESTABLECER'), findsNothing);
      expect(find.textContaining('estado de fábrica'), findsOneWidget);
    });
  });
}
