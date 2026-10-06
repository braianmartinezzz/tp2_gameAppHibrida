import 'dart:convert';
import 'dart:math';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/coin_component.dart';
import 'package:runner_flutter/game/juice.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/screens/home_screen.dart';
import 'package:runner_flutter/state/game_state.dart';
import 'package:runner_flutter/state/rewards.dart';
import 'package:runner_flutter/state/settings_store.dart';
import 'package:runner_flutter/widgets/diamond_shop_modal.dart';
import 'package:runner_flutter/widgets/game_controls.dart';
import 'package:runner_flutter/widgets/rewards_modal.dart';

class _FakeStore extends SettingsStore {
  _FakeStore({this.initial});

  final Map<String, dynamic>? initial;
  Map<String, dynamic>? saved;

  @override
  Future<Map<String, dynamic>?> load() async => initial;

  @override
  Future<void> save(Map<String, dynamic> data) async => saved = data;
}

/// Completa un desafío sin importar de qué tipo sea.
void _complete(GameState state, ChallengeDef c) {
  if (c.isMax) {
    state.addScore(c.target);
  } else {
    state.recordEvent(c.metric, c.target);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final today = DateTime(2026, 10, 3, 12);

  group('vidas', () {
    test('arrancan en 2, bajan hasta 0 sin pasarse y resetRun las repone', () {
      final state = GameState();
      expect(GameState.maxLives, 2);
      expect(state.lives.value, 2);

      expect(state.loseLife(), 1);
      expect(state.loseLife(), 0);
      expect(state.loseLife(), 0, reason: 'nunca negativas');

      state.resetRun();
      expect(state.lives.value, 2);
    });

    test('perder vidas no toca los diamantes (recursos separados)', () {
      final state = GameState();
      final before = state.diamonds.value;
      state.loseLife();
      expect(state.diamonds.value, before);
    });
  });

  group('diamantes recolectados (+1 a +5)', () {
    test('collectDiamond(5) suma a la billetera y a la partida', () {
      final state = GameState();
      final before = state.diamonds.value;
      state.collectDiamond(5);
      expect(state.diamonds.value, before + 5);
      expect(state.runDiamonds.value, 5);
    });

    testWidgets('todos los patrones dan entre 1 y 5; el alto tiene la de 5',
        (tester) async {
      final game = RunnerGame(gameState: GameState());
      await tester.pumpWidget(GameWidget(game: game));

      for (final pattern in CoinPattern.values) {
        final coins = game.spawnCoinPattern(
          pattern: pattern,
          anchorLane: 0,
          avoidObstacles: false,
        );
        expect(coins, isNotEmpty);
        for (final c in coins) {
          expect(c.value, inInclusiveRange(1, 5), reason: '$pattern');
        }
        if (pattern == CoinPattern.high) {
          expect(coins.map((c) => c.value), [2, 2, 5, 2, 2]);
          expect(coins[2].isGolden, isTrue);
        }
        if (pattern == CoinPattern.line) {
          expect(coins.every((c) => c.value == 1 && !c.isGolden), isTrue);
        }
      }
    });

    test('la etiqueta flotante lleva el valor y las doradas, su color', () {
      final juice = Juice(random: Random(1));
      juice.coinPickup(Offset.zero, value: 5);
      juice.coinPickup(Offset.zero);

      expect(juice.labels.first.value, 5);
      expect(juice.labels.first.color, Juice.goldColor);
      expect(juice.labels.last.value, 1);
      expect(juice.labels.last.color, Juice.coinColor);
    });
  });

  group('hitos de puntaje', () {
    test('cada hito se cobra una sola vez y avisa', () {
      final state = GameState();
      final start = state.diamonds.value;

      state.addScore(400);
      expect(state.diamonds.value, start, reason: 'todavía no llegó a 500');

      state.addScore(200); // 600
      expect(state.diamonds.value, start + 5);
      expect(state.claimedMilestones, {500});
      expect(state.rewardEvent.value?.diamonds, 5);

      state.addScore(500); // 1100
      expect(state.diamonds.value, start + 5 + 10);
      expect(state.rewardEvent.value?.title, contains('1000'));

      state.addScore(10);
      expect(state.diamonds.value, start + 15, reason: 'no se repite');
    });

    test('un salto grande cobra todos los hitos que cruza', () {
      final state = GameState();
      final start = state.diamonds.value;
      state.addScore(3000);
      expect(state.claimedMilestones, {500, 1000, 2500});
      expect(state.diamonds.value, start + 5 + 10 + 20);
    });

    test('con la partida terminada no se cobra', () {
      final state = GameState();
      state.finishRun();
      final start = state.diamonds.value;
      state.addScore(600);
      expect(state.diamonds.value, start);
    });
  });

  group('desafíos diarios', () {
    test('hay tres, de métricas distintas y con premio de 10 a 50', () {
      final state = GameState(clock: () => today);
      final list = state.challenges;

      expect(list, hasLength(3));
      expect(list.map((c) => c.metric).toSet(), hasLength(3));
      for (final c in list) {
        expect(c.reward, inInclusiveRange(10, 50));
      }
    });

    test('son los mismos todo el día, para cualquier arranque', () {
      final a = GameState(clock: () => today).challenges.map((c) => c.id);
      final b = GameState(clock: () => today.add(const Duration(hours: 8)))
          .challenges
          .map((c) => c.id);
      expect(a.toList(), b.toList());
    });

    test('progreso, cumplimiento y cobro', () {
      final state = GameState(clock: () => today);
      final c = state.challenges.first;
      final start = state.diamonds.value;

      expect(state.claimChallenge(c), isFalse, reason: 'todavía no está');
      expect(state.claimable.value, 0);

      _complete(state, c);
      expect(state.isChallengeComplete(c), isTrue);
      expect(state.claimable.value, 1);
      expect(state.rewardEvent.value?.title, contains('Desafío cumplido'));

      expect(state.claimChallenge(c), isTrue);
      expect(state.diamonds.value, greaterThanOrEqualTo(start + c.reward));
      expect(state.isChallengeClaimed(c), isTrue);
      expect(state.claimable.value, 0);
      expect(state.claimChallenge(c), isFalse, reason: 'no se cobra dos veces');
    });

    test('el progreso no pasa del objetivo', () {
      final state = GameState(clock: () => today);
      final c = state.challenges.firstWhere((c) => !c.isMax);
      state.recordEvent(c.metric, c.target * 3);
      expect(state.challengeProgress(c), c.target);
    });

    test('se renuevan al cambiar el día', () {
      var now = today;
      final state = GameState(clock: () => now);
      final c = state.challenges.first;
      _complete(state, c);
      state.claimChallenge(c);
      state.grantAdReward();
      expect(state.adsLeftToday, GameState.maxAdsPerDay - 1);

      now = today.add(const Duration(days: 1));
      expect(state.challengeProgress(state.challenges.first), 0);
      expect(state.claimable.value, 0);
      expect(state.adsLeftToday, GameState.maxAdsPerDay);
    });
  });

  group('anuncios voluntarios', () {
    test('dan entre 5 y 20 diamantes y tienen cupo diario', () {
      var now = today;
      final state = GameState(clock: () => now, random: Random(7));
      final start = state.diamonds.value;
      var total = 0;

      for (var i = 0; i < GameState.maxAdsPerDay; i++) {
        final amount = state.grantAdReward();
        expect(amount, inInclusiveRange(5, 20));
        total += amount;
      }
      expect(state.diamonds.value, start + total);
      expect(state.adsLeftToday, 0);
      expect(state.grantAdReward(), 0, reason: 'cupo agotado');
      expect(state.diamonds.value, start + total);

      now = today.add(const Duration(days: 1));
      expect(state.grantAdReward(), greaterThan(0), reason: 'mañana hay más');
    });

    test('el premio cubre todo el rango con el tiempo', () {
      final seen = <int>{};
      for (var seed = 0; seed < 200; seed++) {
        seen.add(GameState(clock: () => today, random: Random(seed))
            .grantAdReward());
      }
      expect(seen.reduce(min), 5);
      expect(seen.reduce(max), 20);
    });
  });

  group('mejoras', () {
    UpgradeDef def(String id) => kUpgrades.firstWhere((u) => u.id == id);

    test('comprar gasta diamantes, sube el nivel y respeta el máximo', () {
      final state = GameState()..diamonds.value = 100;

      expect(state.buyUpgrade(def(UpgradeIds.startShield)), isTrue);
      expect(state.diamonds.value, 40);
      expect(state.upgradeLevel(UpgradeIds.startShield), 1);
      expect(state.buyUpgrade(def(UpgradeIds.startShield)), isFalse,
          reason: 'ya está al máximo');

      expect(state.buyUpgrade(def(UpgradeIds.magnet)), isTrue); // 40
      expect(state.diamonds.value, 0);
      expect(state.buyUpgrade(def(UpgradeIds.magnet)), isFalse,
          reason: 'el nivel 2 cuesta 80');
      expect(state.upgradeLevel(UpgradeIds.magnet), 1);
    });

    testWidgets('escudo inicial y duraciones se aplican al arrancar',
        (tester) async {
      final state = GameState()..diamonds.value = 1000;
      state
        ..buyUpgrade(def(UpgradeIds.startShield))
        ..buyUpgrade(def(UpgradeIds.magnet))
        ..buyUpgrade(def(UpgradeIds.magnet))
        ..buyUpgrade(def(UpgradeIds.multiplier));
      final game = RunnerGame(gameState: state);
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 50));

      expect(game.powerUps.hasShield, isTrue, reason: 'arranca con escudo');

      game.restartRun();
      expect(game.powerUps.hasShield, isTrue, reason: 'también al reiniciar');
      expect(game.powerUps.magnetDuration, 10, reason: '6 s + 2 niveles de 2 s');
      expect(game.powerUps.multiplierDuration, 10);
    });

    testWidgets('sin mejoras, la partida arranca sin escudo', (tester) async {
      final game = RunnerGame(gameState: GameState());
      await tester.pumpWidget(GameWidget(game: game));
      await tester.pump(const Duration(milliseconds: 50));
      expect(game.powerUps.hasShield, isFalse);
      expect(game.powerUps.magnetDuration, 6);
    });
  });

  group('persistencia', () {
    test('lo ganado vuelve igual al reabrir la app', () async {
      final store = _FakeStore();
      final a = GameState(store: store, clock: () => today, random: Random(3));
      a.diamonds.value = 300;
      a.buyUpgrade(kUpgrades[1]); // imán nivel 1
      a.addScore(1200); // hitos 500 y 1000
      final c = a.challenges.first;
      _complete(a, c);
      a.claimChallenge(c);
      a.grantAdReward();
      a.save();

      // Pasa por JSON como en el disco real.
      final onDisk = jsonDecode(jsonEncode(store.saved)) as Map<String, dynamic>;

      final b = GameState(
        store: _FakeStore(initial: onDisk),
        clock: () => today,
      );
      await b.loadSettings();

      expect(b.diamonds.value, a.diamonds.value);
      expect(b.upgradeLevel(UpgradeIds.magnet), 1);
      expect(b.claimedMilestones, a.claimedMilestones);
      expect(b.claimedMilestones, containsAll([500, 1000]));
      expect(b.isChallengeClaimed(b.challenges.first), isTrue);
      expect(b.adsLeftToday, a.adsLeftToday);
    });

    test('los desafíos guardados de otro día se descartan, lo demás queda',
        () async {
      final store = _FakeStore();
      final a = GameState(store: store, clock: () => today);
      a.diamonds.value = 123;
      final c = a.challenges.first;
      _complete(a, c);
      a.claimChallenge(c);
      a.save();

      final tomorrow = today.add(const Duration(days: 1));
      final b = GameState(
        store: _FakeStore(initial: store.saved),
        clock: () => tomorrow,
      );
      await b.loadSettings();

      expect(b.diamonds.value, a.diamonds.value, reason: 'la billetera queda');
      expect(b.claimable.value, 0);
      for (final ch in b.challenges) {
        expect(b.isChallengeClaimed(ch), isFalse);
        expect(b.challengeProgress(ch), 0);
      }
      expect(b.adsLeftToday, GameState.maxAdsPerDay);
    });

    test('un guardado corrupto no rompe nada', () async {
      final b = GameState(
        store: _FakeStore(initial: {
          'diamonds': 'muchos',
          'upgrades': 7,
          'milestones': 'x',
          'daily': {'day': dayKey(today), 'progress': 3},
          'swipeSensitivity': 'alta',
        }),
        clock: () => today,
      );
      await b.loadSettings();
      expect(b.diamonds.value, 85);
      expect(b.challenges, hasLength(3));
    });
  });

  group('pantallas', () {
    testWidgets('corazones en la partida: bajan al perder una vida',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final state = GameState()..tutorialSeen.value = true;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(gameState: state)));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.byIcon(Icons.favorite_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);

      state.loseLife();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets(
        'la botonera no tiene Premios y los rótulos están en español; '
        'Premios se abre desde el game over con el número de pendientes',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 760));
      final state = GameState(clock: () => today)..tutorialSeen.value = true;
      await tester.pumpWidget(MaterialApp(home: HomeScreen(gameState: state)));
      await tester.pump(const Duration(milliseconds: 600));

      Finder inControls(String text) => find.descendant(
            of: find.byType(GameControls),
            matching: find.text(text),
          );
      expect(inControls('Premios'), findsNothing);
      for (final label in ['Jugar', 'Pausa', 'Reiniciar']) {
        expect(inControls(label), findsOneWidget);
      }
      for (final english in ['Play', 'Pause', 'Reset']) {
        expect(inControls(english), findsNothing);
      }

      _complete(state, state.challenges.first);
      await tester.pump();
      expect(state.claimable.value, 1);

      state.finishRun();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('rewards-button')), findsOneWidget);
      expect(find.text('Premios (1)'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('modal de premios: reclamar un desafío y ver un anuncio',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 1000));
      final state = GameState(clock: () => today, random: Random(5));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showRewardsModal(context, state),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Desafíos de hoy'), findsOneWidget);
      expect(find.text('Hitos de puntaje'), findsOneWidget);
      expect(find.text('500 pts'), findsOneWidget);

      final c = state.challenges.first;
      final start = state.diamonds.value;
      _complete(state, c);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reclamar +${c.reward}'));
      await tester.pumpAndSettle();
      expect(find.text('Cobrado'), findsOneWidget);
      expect(state.diamonds.value, greaterThanOrEqualTo(start + c.reward));

      // Anuncio voluntario: 3 s de cuenta y recién ahí se cobra.
      await tester.ensureVisible(find.text('Ver anuncio'));
      await tester.pumpAndSettle();
      final beforeAd = state.diamonds.value;
      await tester.tap(find.text('Ver anuncio'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Anuncio simulado'), findsOneWidget);
      expect(state.diamonds.value, beforeAd, reason: 'antes de verlo no paga');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();

      expect(state.diamonds.value, greaterThanOrEqualTo(beforeAd + 5));
      expect(state.diamonds.value, lessThanOrEqualTo(beforeAd + 20));
      expect(find.textContaining('¡Ganaste +'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('tienda: comprar una mejora con diamantes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(480, 1000));
      final state = GameState(); // 85 diamantes
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDiamondShopModal(context, state),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      expect(find.text('Escudo inicial'), findsOneWidget);
      // El escudo cuesta 60 y alcanza; el imán nivel 1 (40) también.
      await tester.tap(find.text('60'));
      await tester.pumpAndSettle();

      expect(state.diamonds.value, 25);
      expect(state.upgradeLevel(UpgradeIds.startShield), 1);
      expect(find.text('MÁX'), findsOneWidget);
      await tester.binding.setSurfaceSize(null);
    });
  });
}
