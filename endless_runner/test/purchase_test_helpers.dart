import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pantalla alta para que las hojas de compra entren sin scroll.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Lee la cuenta de la puerta parental ("27 + 31") y devuelve el resultado.
int parentalAnswer(WidgetTester tester) {
  final text = tester
      .widget<Text>(find.byKey(const ValueKey('gate-question')))
      .data!;
  final parts = text.split(' + ');
  return int.parse(parts[0]) + int.parse(parts[1]);
}

/// Resuelve bien la puerta parental.
Future<void> solveParentalGate(WidgetTester tester) async {
  await tester.tap(find.byKey(ValueKey('gate-option-${parentalAnswer(tester)}')));
}

/// Toca una opción incorrecta de la puerta parental.
Future<void> failParentalGate(WidgetTester tester) async {
  final answer = parentalAnswer(tester);
  final wrong = tester
      .widgetList<OutlinedButton>(find.byType(OutlinedButton))
      .map((b) => int.parse((b.child! as Text).data!))
      .firstWhere((v) => v != answer);
  await tester.tap(find.byKey(ValueKey('gate-option-$wrong')));
}
