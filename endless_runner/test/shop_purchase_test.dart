import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/widgets/diamond_shop_modal.dart';

import 'purchase_test_helpers.dart';

void main() {
  Future<void> openShop(WidgetTester tester, GameState state) async {
    useTallSurface(tester);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDiamondShopModal(context, state),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  Future<void> tapPack(WidgetTester tester, String price) async {
    await tester.ensureVisible(find.text(price));
    await tester.pumpAndSettle();
    await tester.tap(find.text(price));
    await tester.pumpAndSettle();
  }

  group('Tienda: packs de diamantes con flujo de pago', () {
    testWidgets('comprar un pack pide la puerta parental y suma diamantes',
        (tester) async {
      final state = GameState();
      final before = state.diamonds.value;
      await openShop(tester, state);

      await tapPack(tester, '\$1.99');
      expect(find.text('Pagar \$1.99'), findsOneWidget);
      expect(state.diamonds.value, before, reason: 'todavía no pagó');

      await tester.tap(find.byKey(const ValueKey('purchase-pay-button')));
      await tester.pumpAndSettle();
      expect(state.diamonds.value, before, reason: 'falta la puerta parental');

      await solveParentalGate(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();
      expect(state.diamonds.value, before + 100);
      expect(find.text('¡Listo! +100 diamantes'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('purchase-done-button')));
      await tester.pumpAndSettle();
      expect(find.text('Tienda'), findsOneWidget, reason: 'la tienda sigue');
    });

    testWidgets('cancelar la compra no suma nada', (tester) async {
      final state = GameState();
      final before = state.diamonds.value;
      await openShop(tester, state);

      await tapPack(tester, '\$4.99');
      await tester.tap(find.byKey(const ValueKey('purchase-cancel-button')));
      await tester.pumpAndSettle();

      expect(state.diamonds.value, before);
      expect(find.text('Tienda'), findsOneWidget);
    });
  });
}
