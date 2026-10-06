import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/widgets/purchase_flow.dart';

import 'purchase_test_helpers.dart';

void main() {
  group('ParentalQuestion', () {
    test('siempre ofrece 3 opciones distintas, positivas y con la correcta', () {
      for (var seed = 0; seed < 200; seed++) {
        final q = ParentalQuestion.generate(Random(seed));
        expect(q.options.length, 3, reason: 'semilla $seed');
        expect(q.options.toSet().length, 3, reason: 'semilla $seed');
        expect(q.options, contains(q.answer));
        expect(q.options.every((o) => o > 0), isTrue);
        // Dos cifras: un chico que no sabe sumar así no la adivina.
        expect(q.a, greaterThanOrEqualTo(12));
        expect(q.b, greaterThanOrEqualTo(13));
      }
    });
  });

  group('showPurchaseFlow', () {
    late int paid;
    bool? result;

    setUp(() {
      paid = 0;
      result = null;
    });

    Future<void> open(WidgetTester tester) async {
      useTallSurface(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showPurchaseFlow(
                  context,
                  PurchaseItem(
                    title: 'Pack de prueba',
                    price: '\$1.99',
                    icon: const Icon(Icons.diamond_rounded),
                    summary: const Text('Incluye 100 diamantes'),
                    onPaid: () => paid++,
                    successTitle: '¡Compra lista!',
                  ),
                  random: Random(7),
                  processingDelay: const Duration(milliseconds: 100),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    testWidgets('flujo completo: resumen, puerta parental, pago y éxito',
        (tester) async {
      await open(tester);
      expect(find.text('Pack de prueba'), findsOneWidget);
      expect(find.text('Pagar \$1.99'), findsOneWidget);
      expect(paid, 0);

      await tester.tap(find.byKey(const ValueKey('purchase-pay-button')));
      await tester.pumpAndSettle();
      expect(find.text('Pedile a una persona adulta'), findsOneWidget);
      expect(paid, 0, reason: 'sin resolver la cuenta no se paga');

      await solveParentalGate(tester);
      await tester.pump();
      expect(find.text('Procesando el pago…'), findsOneWidget);
      expect(paid, 0, reason: 'todavía procesando');

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(paid, 1);
      expect(find.text('¡Compra lista!'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('purchase-done-button')));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(find.text('Pack de prueba'), findsNothing);
    });

    testWidgets('una respuesta incorrecta no cobra y cambia la cuenta',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('purchase-pay-button')));
      await tester.pumpAndSettle();

      await failParentalGate(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gate-wrong')), findsOneWidget);
      expect(paid, 0);
      expect(find.text('Procesando el pago…'), findsNothing);

      // Con la cuenta nueva sí se puede seguir.
      await solveParentalGate(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(paid, 1);
    });

    testWidgets('"Ahora no" cierra sin cobrar', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('purchase-cancel-button')));
      await tester.pumpAndSettle();
      expect(paid, 0);
      expect(result, isFalse);
      expect(find.text('Pack de prueba'), findsNothing);
    });

    testWidgets('cancelar en la puerta parental cierra sin cobrar',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('purchase-pay-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('purchase-gate-cancel')));
      await tester.pumpAndSettle();
      expect(paid, 0);
      expect(result, isFalse);
    });

    testWidgets('pago rechazado: no cobra y el reintento sale bien',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('purchase-reject-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('purchase-pay-button')));
      await tester.pumpAndSettle();
      await solveParentalGate(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('No pudimos procesar el pago'), findsOneWidget);
      expect(paid, 0, reason: 'un pago rechazado no entrega nada');

      await tester.tap(find.byKey(const ValueKey('purchase-retry-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(paid, 1, reason: 'se entrega una sola vez');
      expect(find.text('¡Compra lista!'), findsOneWidget);
    });

    testWidgets('pago rechazado y "Cerrar": no entrega nada', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('purchase-reject-toggle')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('purchase-pay-button')));
      await tester.pumpAndSettle();
      await solveParentalGate(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('purchase-close-button')));
      await tester.pumpAndSettle();
      expect(paid, 0);
      expect(result, isFalse);
    });
  });
}
