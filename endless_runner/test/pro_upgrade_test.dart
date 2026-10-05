import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/settings_store.dart';
import 'package:runner_flutter/widgets/game_header.dart';

class _FakeStore extends SettingsStore {
  _FakeStore({this.initial});

  final Map<String, dynamic>? initial;
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>?> load() async => initial;

  @override
  Future<void> save(Map<String, dynamic> data) async => saved = data;
}

void main() {
  group('Mejorar a Pro (estado)', () {
    test('arranca basic con 2 corazones', () {
      final state = GameState();
      expect(state.isPro, isFalse);
      expect(state.startingLives, GameState.maxLives);
    });

    test('upgradeToPro pasa a pro y da un corazón extra por partida', () {
      final state = GameState();
      expect(state.upgradeToPro(), isTrue);
      expect(state.isPro, isTrue);
      expect(state.startingLives, GameState.proMaxLives);

      state.resetRun();
      expect(state.lives.value, GameState.proMaxLives);
    });

    test('mejorar en plena partida suma el corazón al instante', () {
      final state = GameState();
      state.upgradeToPro();
      expect(state.lives.value, GameState.maxLives + 1);
    });

    test('con la partida terminada no revive al mejorar', () {
      final state = GameState()
        ..loseLife()
        ..loseLife()
        ..finishRun();
      state.upgradeToPro();
      expect(state.lives.value, 0);
    });

    test('una cuenta Pro no se puede "mejorar" otra vez', () {
      final state = GameState()..upgradeToPro();
      expect(state.upgradeToPro(), isFalse);
    });

    test('se guarda y se restaura', () async {
      final store = _FakeStore();
      GameState(store: store).upgradeToPro();
      await Future<void>.delayed(Duration.zero);
      expect(store.saved?['pro'], isTrue);

      final loaded = GameState(store: _FakeStore(initial: {'pro': true}));
      await loaded.loadSettings();
      expect(loaded.isPro, isTrue);
      expect(loaded.lives.value, GameState.proMaxLives);
    });

    test('un save viejo sin la clave sigue siendo basic', () async {
      final loaded = GameState(store: _FakeStore(initial: {'diamonds': 10}));
      await loaded.loadSettings();
      expect(loaded.isPro, isFalse);
    });
  });

  group('Mejorar a Pro (UI)', () {
    testWidgets('tocar el badge BASIC abre el menú y comprar pasa a Pro',
        (tester) async {
      final state = GameState();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameHeader(gameState: state)),
      ));

      await tester.tap(find.byKey(const ValueKey('account-badge')));
      await tester.pumpAndSettle();
      expect(find.text('Mejorar a Pro'), findsOneWidget);
      expect(find.text('Sin anuncios'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pro-buy-button')));
      await tester.pump(); // arranca el "pago"
      expect(find.text('Procesando el pago…'), findsOneWidget);
      expect(state.isPro, isFalse);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(state.isPro, isTrue);
      expect(find.text('¡Ya sos Pro!'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pro-done-button')));
      await tester.pumpAndSettle();
      expect(find.text('PRO'), findsOneWidget);
    });

    testWidgets('"Ahora no" cierra sin cambiar la cuenta', (tester) async {
      final state = GameState();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: GameHeader(gameState: state)),
      ));

      await tester.tap(find.byKey(const ValueKey('account-badge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pro-close-button')));
      await tester.pumpAndSettle();

      expect(state.isPro, isFalse);
      expect(find.text('Mejorar a Pro'), findsNothing);
    });
  });
}
