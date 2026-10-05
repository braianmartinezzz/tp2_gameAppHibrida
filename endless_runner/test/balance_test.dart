import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/rewards.dart';
import 'package:runner_flutter/widgets/game_over_overlay.dart';

UpgradeDef _def(String id) => kUpgrades.firstWhere((u) => u.id == id);

void main() {
  group('balance de diamantes: mejoras nuevas', () {
    test('hay más cosas en qué gastar: el total de la tienda pasa de 600', () {
      final total = kUpgrades.fold<int>(
        0,
        (sum, u) => sum + u.costs.fold<int>(0, (a, b) => a + b),
      );
      expect(total, greaterThan(2000));
    });

    test('los ids de las mejoras son únicos', () {
      final ids = kUpgrades.map((u) => u.id).toSet();
      expect(ids.length, kUpgrades.length);
    });

    test('corazón extra: sube las vidas iniciales y también Pro suma', () {
      final state = GameState()..diamonds.value = 1000;
      expect(state.startingLives, GameState.maxLives);

      expect(state.buyUpgrade(_def(UpgradeIds.extraHeart)), isTrue);
      expect(state.startingLives, GameState.maxLives + 1);
      expect(state.lives.value, GameState.maxLives + 1,
          reason: 'se nota en la partida en curso');

      state.upgradeToPro();
      expect(state.startingLives, GameState.proMaxLives + 1);

      state.resetRun();
      expect(state.lives.value, GameState.proMaxLives + 1);
    });

    test('corazón extra comprado con la partida terminada no revive', () {
      final state = GameState()
        ..diamonds.value = 1000
        ..loseLife()
        ..loseLife()
        ..finishRun();
      state.buyUpgrade(_def(UpgradeIds.extraHeart));
      expect(state.lives.value, 0);
    });

    test('las mejoras nuevas quedan en el JSON del guardado', () {
      final state = GameState()..diamonds.value = 1000;
      state
        ..buyUpgrade(_def(UpgradeIds.luck))
        ..buyUpgrade(_def(UpgradeIds.startMagnet))
        ..buyUpgrade(_def(UpgradeIds.startMagnet));
      final json = state.toJson();
      expect(json['upgrades'], containsPair(UpgradeIds.luck, 1));
      expect(json['upgrades'], containsPair(UpgradeIds.startMagnet, 2));
    });
  });

  group('balance de diamantes: revivir pagando', () {
    test('cuesta ${GameState.reviveDiamondCost} y deja revivir una vez', () {
      final state = GameState()
        ..diamonds.value = 100
        ..finishRun();
      expect(state.canPayRevive, isTrue);
      expect(state.payRevive(), isTrue);
      expect(state.diamonds.value, 100 - GameState.reviveDiamondCost);
      expect(state.revive(), isTrue);

      state.finishRun();
      expect(state.canPayRevive, isFalse, reason: 'una sola vez por partida');
    });

    test('sin saldo no se cobra ni se revive', () {
      final state = GameState()
        ..diamonds.value = GameState.reviveDiamondCost - 1
        ..finishRun();
      expect(state.canPayRevive, isFalse);
      expect(state.payRevive(), isFalse);
      expect(state.diamonds.value, GameState.reviveDiamondCost - 1);
    });

    test('la cuenta Pro no paga: revive gratis', () {
      final state = GameState()
        ..diamonds.value = 500
        ..upgradeToPro()
        ..finishRun();
      expect(state.canPayRevive, isFalse);
      expect(state.payRevive(), isFalse);
      expect(state.diamonds.value, 500);
    });

    Future<void> pump(WidgetTester tester, GameState state,
        {VoidCallback? onPay}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GameOverOverlay(
            gameState: state,
            onRestart: () {},
            onRevive: () {},
            onReviveWithDiamonds: onPay,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('el botón aparece, está activo con saldo y avisa al tocar',
        (tester) async {
      final state = GameState()
        ..diamonds.value = 100
        ..finishRun();
      var taps = 0;
      await pump(tester, state, onPay: () => taps++);

      expect(find.text('Revivir con 60 diamantes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('revive-diamonds-button')));
      expect(taps, 1);
    });

    testWidgets('sin saldo el botón está deshabilitado', (tester) async {
      final state = GameState()
        ..diamonds.value = 10
        ..finishRun();
      var taps = 0;
      await pump(tester, state, onPay: () => taps++);

      await tester.tap(find.byKey(const ValueKey('revive-diamonds-button')),
          warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('la cuenta Pro no ve el botón de pagar', (tester) async {
      final state = GameState()
        ..upgradeToPro()
        ..finishRun();
      await pump(tester, state, onPay: () {});
      expect(find.byKey(const ValueKey('revive-diamonds-button')),
          findsNothing);
    });
  });
}
