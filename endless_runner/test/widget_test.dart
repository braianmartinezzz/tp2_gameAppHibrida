import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/widgets/game_header.dart';

void main() {
  testWidgets('el header muestra usuario, score y diamantes', (
    WidgetTester tester,
  ) async {
    final gameState = GameState();

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: GameHeader(gameState: gameState))),
    );

    expect(find.text('braian_123'), findsOneWidget);
    expect(find.text('score: 0'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
    expect(find.text('BASIC'), findsOneWidget);

    gameState.addScore(42);
    await tester.pump();

    expect(find.text('score: 42'), findsOneWidget);
    expect(find.text('score: 0'), findsNothing);
  });
}
