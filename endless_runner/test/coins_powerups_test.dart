import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:runner_flutter/game/coin_component.dart';
import 'package:runner_flutter/game/depth_component.dart';
import 'package:runner_flutter/game/obstacle_component.dart';
import 'package:runner_flutter/game/perspective.dart';
import 'package:runner_flutter/game/player_component.dart';
import 'package:runner_flutter/game/power_up_component.dart';
import 'package:runner_flutter/game/power_up_state.dart';
import 'package:runner_flutter/game/runner_game.dart';
import 'package:runner_flutter/state/game_state.dart';

/// Geometría fija de las pruebas unitarias (480x760, como el preview).
const _p = Perspective(width: 480, height: 760);

PlayerComponent _player() => PlayerComponent(
      startPosition: Vector2(_p.width * 0.5, _p.height * 0.86),
      perspective: _p,
    );

/// Jugador con [seconds] de salto en las piernas (0.15 s ≈ 43 px de altura).
PlayerComponent _jumping({double seconds = 0.15}) {
  final player = _player();
  player.jump();
  const step = 1 / 120;
  for (var t = 0.0; t < seconds; t += step) {
    player.update(step);
  }
  return player;
}

/// Moneda en el carril [lane] exactamente en la fila del jugador.
CoinComponent _atRow(
  PlayerComponent player, {
  double lane = 0,
  bool elevated = false,
}) {
  final coin = CoinComponent(
    lane: lane,
    perspective: _p,
    speed: 0,
    spawnT: 0.5, // lejos del horizonte: arranca con alpha 1
    elevated: elevated,
  );
  coin.baseY = player.groundFeetY;
  coin.syncGeometry();
  return coin;
}

/// Bombea hasta que cada moneda de [coins] quedó fuera de la fila del jugador
/// (o directamente fuera del corredor), con tope de frames.
///
/// Saltea los dos primeros frames: Flame encola el `add()` y recién en el
/// siguiente ciclo entra al árbol, así que recién ahí tienen sentido las
/// lecturas de `children`.
Future<void> _pumpPastRow(
  WidgetTester tester,
  RunnerGame game,
  List<CoinComponent> coins, {
  int maxPumps = 500,
}) async {
  final row = game.player.groundFeetY + DepthComponent.depthMargin;
  for (var i = 0; i < maxPumps; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    if (i < 2) continue;
    if (coins.every((c) => !game.children.contains(c) || c.baseY > row)) {
      break;
    }
  }
}

/// ¿La moneda quedó congelada dentro de la fila de recolección (la recogieron)
/// o pasó de largo? Como la cadena se estira, una moneda puede salir del
/// corredor *antes* de que las últimas lleguen a la fila: por eso lo que se
/// mira es el `baseY` congelado al desaparecer, no si sigue en el árbol.
bool _wasCollected(RunnerGame game, CoinComponent coin) =>
    coin.baseY <= game.player.groundFeetY + DepthComponent.depthMargin;

/// Piloto automático: se planta en el carril del próximo obstáculo.
void _driveToNextObstacle(RunnerGame game) {
  final feet = game.player.groundFeetY;
  final ahead = game.children
      .whereType<ObstacleComponent>()
      .where((o) => o.baseY < feet + 5) // que todavía no pasó
      .toList()
    ..sort((a, b) => b.baseY.compareTo(a.baseY)); // más cercano primero
  if (ahead.isNotEmpty) {
    game.player.lane = ahead.first.lane.round();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  // Patrones: geometría y gestos que exigen.
  // -------------------------------------------------------------------------
  group('patrones de monedas', () {
    test('cada patrón cabe en el corredor y se estira hacia el jugador', () {
      for (final pattern in CoinPattern.values) {
        for (final anchor in pattern.anchorCandidates) {
          final coins = buildCoinPattern(
            pattern: pattern,
            perspective: _p,
            speed: 300,
            anchorLane: anchor,
          );

          expect(coins, isNotEmpty, reason: '$pattern con anclaje $anchor');
          expect(
            coins.last.baseY,
            greaterThan(coins.first.baseY),
            reason: '$pattern: la cadena se estira hacia el jugador',
          );

          for (final coin in coins) {
            expect(coin.lane, inInclusiveRange(-1.0, 1.0));
            expect(coin.position.x, greaterThanOrEqualTo(0));
            expect(
              coin.position.x + coin.size.x,
              lessThanOrEqualTo(_p.width),
              reason: 'la moneda se dibuja completa en pantalla',
            );
            expect(coin.alpha, inInclusiveRange(0.0, 1.0));
          }
        }
      }
    });

    test('el dibujo exacto de cada patrón es estable', () {
      String lanes(CoinPattern p, double anchor) => buildCoinPattern(
            pattern: p,
            perspective: _p,
            speed: 300,
            anchorLane: anchor,
          ).map((c) => c.lane.toStringAsFixed(2)).join(',');

      expect(lanes(CoinPattern.line, 1),
          '1.00,1.00,1.00,1.00,1.00,1.00,1.00');
      expect(lanes(CoinPattern.arc, -0.5),
          '-0.95,-0.80,-0.65,-0.50,-0.35,-0.20,-0.05');
      expect(lanes(CoinPattern.zigzag, 0.5),
          '0.00,0.00,0.00,0.00,1.00,1.00,1.00,1.00,0.00,0.00');
      expect(lanes(CoinPattern.high, 0), '0.00,0.00,0.00,0.00,0.00');

      final arc = buildCoinPattern(
        pattern: CoinPattern.arc,
        perspective: _p,
        speed: 300,
        anchorLane: -0.5,
      );
      expect(
        arc.map((c) => c.spawnT.toStringAsFixed(3)).join(','),
        '0.130,0.144,0.158,0.172,0.186,0.200,0.214',
        reason: 'cada moneda nace con fade propio desde t = 0.13',
      );
      expect(arc.first.alpha, 0, reason: 'recién nacida: entra apareciendo');
    });

    test('las monedas del suelo se recogen parado y agachado', () {
      final standing = _player();
      expect(
        _atRow(standing).collidesWith(standing),
        isTrue,
        reason: 'parado las pisa',
      );

      final rolling = _player()..roll();
      expect(
        _atRow(rolling).collidesWith(rolling),
        isTrue,
        reason: 'agachado también (la caja sigue apoyada)',
      );

      final jumping = _jumping();
      expect(
        _atRow(jumping).collidesWith(jumping),
        isFalse,
        reason: 'saltando por encima las pisa en el aire',
      );
    });

    test('las monedas altas exigen salto', () {
      final standing = _player();
      expect(
        _atRow(standing, elevated: true).collidesWith(standing),
        isFalse,
        reason: 'parado llega hasta 34 px y la nube arranca en 56',
      );

      final rolling = _player()..roll();
      expect(
        _atRow(rolling, elevated: true).collidesWith(rolling),
        isFalse,
        reason: 'agachado baja todavía más la caja',
      );

      final jumping = _jumping();
      expect(jumping.jumpY, greaterThan(20));
      expect(
        _atRow(jumping, elevated: true).collidesWith(jumping),
        isTrue,
        reason: 'la parábola entra en la nube',
      );
    });

    test('sin solape de carril no se recogen', () {
      final player = _player(); // carril 0
      expect(
        _atRow(player, lane: 1).collidesWith(player),
        isFalse,
        reason: 'el carril vecino queda fuera de alcance',
      );
      expect(_atRow(player, lane: 0).collidesWith(player), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Estado de los power-ups (puro, sin árbol de componentes).
  // -------------------------------------------------------------------------
  group('estado de power-ups', () {
    test('el escudo se aplica una vez, se gasta al golpe y deja respiro', () {
      final state = PowerUpState();
      expect(state.hasShield, isFalse);

      expect(state.apply(PowerUpKind.shield), isTrue);
      expect(state.hasShield, isTrue);
      expect(
        state.apply(PowerUpKind.shield),
        isFalse,
        reason: 'ya tiene uno: no se apila',
      );

      expect(state.absorbHit(), isTrue, reason: 'el primer golpe lo absorbe');
      expect(state.hasShield, isFalse, reason: 'el escudo se rompió');
      expect(state.isInvulnerable, isTrue, reason: 'queda respiro');
      expect(state.absorbHit(), isFalse, reason: 'sin escudo el golpe pasa');

      state.update(state.invulnerableDuration + 0.01);
      expect(state.isInvulnerable, isFalse);
      expect(state.invulnerableTimer, 0, reason: 'los timers nunca bajan de 0');
    });

    test('el imán y el multiplicador vencen con el tiempo', () {
      final state = PowerUpState();
      expect(state.scoreMultiplier, 1);

      expect(state.apply(PowerUpKind.multiplier), isTrue);
      expect(state.scoreMultiplier, 2, reason: 'score en x2');
      expect(state.apply(PowerUpKind.magnet), isTrue);
      expect(state.isMagnetActive, isTrue);
      expect(state.magnetTimer, state.magnetDuration);

      state.update(state.magnetDuration);
      expect(state.isMagnetActive, isFalse, reason: 'el imán se agota');
      expect(state.isMultiplierActive, isTrue, reason: 'el x2 dura más');

      state.update(state.multiplierDuration);
      expect(state.isMultiplierActive, isFalse);
      expect(state.scoreMultiplier, 1);

      state.update(999);
      expect(state.magnetTimer, 0);
      expect(state.multiplierTimer, 0);
    });

    test('reset limpia todo para reiniciar la partida', () {
      final state = PowerUpState()
        ..apply(PowerUpKind.shield)
        ..apply(PowerUpKind.magnet)
        ..apply(PowerUpKind.multiplier);
      state.reset();
      expect(state.hasShield, isFalse);
      expect(state.magnetTimer, 0);
      expect(state.multiplierTimer, 0);
      expect(state.invulnerableTimer, 0);
    });
  });

  // -------------------------------------------------------------------------
  // Recogida end-to-end: patrón → carril → diamantes.
  // -------------------------------------------------------------------------
  testWidgets('cada moneda recogida suma un diamante', (tester) async {
    final gameState = GameState()
      ..diamonds.value = 1000000; // invulnerable: el test mide la recolección
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));

    final start = gameState.diamonds.value;
    final coins = game.spawnCoinPattern(
      pattern: CoinPattern.line,
      anchorLane: 0,
      avoidObstacles: false,
    );
    expect(coins, hasLength(7));
    expect(game.player.lane, 0, reason: 'el jugador espera en el carril');

    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      // Invulnerable a propósito: acá se mide la recolección, y cada choque
      // contra un obstáculo descontaría 10 diamantes y ensuciaría el conteo.
      game.powerUps.grantInvulnerability();
    }

    expect(
      game.children.whereType<CoinComponent>().where(coins.contains),
      isEmpty,
      reason: 'las siete monedas pasaron por el jugador',
    );
    expect(
      gameState.diamonds.value,
      greaterThanOrEqualTo(start + 7),
      reason: 'cada moneda vale un diamante (el imán y los patrones '
          'autogenerados pueden sumar alguno más)',
    );
    expect(gameState.isGameOver.value, isFalse);
  });

  testWidgets('sin imán no se recoge el carril vecino; con imán sí',
      (tester) async {
    final gameState = GameState()..diamonds.value = 1000000;
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));
    expect(game.player.lane, 0);

    // Control: monedas en el carril 1 con el jugador en el 0.
    final far = game.spawnCoinPattern(
      pattern: CoinPattern.line,
      anchorLane: 1,
      avoidObstacles: false,
    );
    expect(far, isNotEmpty);
    await _pumpPastRow(tester, game, far);
    expect(
      far.where((c) => _wasCollected(game, c)),
      isEmpty,
      reason: 'sin imán, el carril vecino queda fuera de alcance',
    );

    // Con imán activo, las chupa aunque vengan de lejos.
    expect(game.powerUps.apply(PowerUpKind.magnet), isTrue);
    final pulled = game.spawnCoinPattern(
      pattern: CoinPattern.line,
      anchorLane: 1,
      avoidObstacles: false,
    );
    expect(pulled, isNotEmpty);
    await _pumpPastRow(tester, game, pulled);
    expect(
      pulled.where((c) => !_wasCollected(game, c)),
      isEmpty,
      reason: 'el imán las trae al carril del jugador antes de que pasen',
    );
    expect(
      pulled.where(game.children.contains),
      isEmpty,
      reason: 'las recogidas desaparecen del corredor',
    );
  });

  // -------------------------------------------------------------------------
  // Invariante: los patrones nunca quedan pegados a un obstáculo.
  // -------------------------------------------------------------------------
  testWidgets('los patrones automáticos nunca caen en un obstáculo',
      (tester) async {
    final gameState = GameState()
      ..diamonds.value = 1000000; // invulnerable: acá solo se mide el spawn
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));

    var sawPattern = false;
    for (var i = 0; i < 1500; i++) {
      await tester.pump(const Duration(milliseconds: 16));

      // El imán puede arrastrar una moneda hacia otro carril a mitad de vuelo:
      // ese movimiento es de la mecánica, no del spawn, así que se saltea.
      if (game.powerUps.isMagnetActive) continue;

      final coins = game.children.whereType<CoinComponent>().toList();
      if (coins.isNotEmpty) sawPattern = true;
      final obstacles = game.children.whereType<ObstacleComponent>().toList();

      for (final coin in coins) {
        for (final obstacle in obstacles) {
          if ((obstacle.baseY - coin.baseY).abs() > 28) continue;
          expect(
            (obstacle.lane - coin.lane).abs(),
            greaterThanOrEqualTo(
              obstacle.laneHalfSpan + coin.laneHalfSpan,
            ),
            reason: 'moneda en carril ${coin.lane} (t=${coin.t.toStringAsFixed(2)})'
                ' dentro del obstáculo en carril ${obstacle.lane}',
          );
        }
      }
    }

    expect(sawPattern, isTrue, reason: 'en ~24 s se generaron patrones');
    expect(gameState.isGameOver.value, isFalse);
  });

  // -------------------------------------------------------------------------
  // Power-ups sueltos en el corredor.
  // -------------------------------------------------------------------------
  testWidgets('el power-up suelto se recoge al tocarlo', (tester) async {
    final gameState = GameState()..diamonds.value = 1000000;
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));

    final item = game.spawnPowerUp(
      kind: PowerUpKind.multiplier,
      lane: 0,
      avoidObstacles: false,
    );
    expect(item, isNotNull);
    expect(game.powerUps.isMultiplierActive, isFalse);

    for (var i = 0; i < 400 && !game.powerUps.isMultiplierActive; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(
      game.powerUps.isMultiplierActive,
      isTrue,
      reason: 'la ficha se recoge al pasar por el carril',
    );
    // Flame encola la baja del árbol: se esperan dos frames a que salga.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(
      game.children.contains(item!),
      isFalse,
      reason: 'el ítem desaparece del corredor',
    );
    expect(game.powerUps.multiplierTimer, greaterThan(0));
  });

  testWidgets('el escudo absorbe el primer golpe y el segundo corta',
      (tester) async {
    final gameState = GameState()..diamonds.value = 0;
    final game = RunnerGame(gameState: gameState);
    await tester.pumpWidget(GameWidget(game: game));
    expect(game.powerUps.apply(PowerUpKind.shield), isTrue);

    // Piloto hasta que choque: el escudo debería volar en el primer impacto.
    // Los diamantes se drenan a mano en cada frame: una moneda accidental
    // habilitaría el "revive" de 10 y ensayaríamos otra mecánica.
    var shieldBroke = false;
    for (var i = 0; i < 1500 && !shieldBroke; i++) {
      gameState.diamonds.value = 0;
      await tester.pump(const Duration(milliseconds: 16));
      _driveToNextObstacle(game);
      shieldBroke = !game.powerUps.hasShield;
    }

    gameState.diamonds.value = 0;
    expect(shieldBroke, isTrue, reason: 'el escudo absorbió el choque');
    expect(gameState.isGameOver.value, isFalse, reason: 'sigue vivo');
    expect(gameState.diamonds.value, 0, reason: 'no gastó diamantes');
    expect(
      game.powerUps.isInvulnerable,
      isTrue,
      reason: 'queda un respiro tras romper el escudo',
    );

    // Sin escudo y sin diamantes, el siguiente choque termina la partida.
    for (var i = 0; i < 2500 && !gameState.isGameOver.value; i++) {
      gameState.diamonds.value = 0;
      await tester.pump(const Duration(milliseconds: 16));
      _driveToNextObstacle(game);
    }

    gameState.diamonds.value = 0;
    expect(gameState.isGameOver.value, isTrue, reason: 'sin escudo ni diamantes');
    expect(gameState.score.value, greaterThan(0));
  });
}
