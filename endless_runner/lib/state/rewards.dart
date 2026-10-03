import 'dart:math';

/// Qué mide un desafío diario.
///
/// [score] es un máximo (mejor puntaje de una sola partida); el resto se
/// acumula a lo largo del día.
enum ChallengeMetric { diamonds, score, jumps, rolls, runs, powerUps }

/// Definición de un desafío: no tiene estado, solo lo que hay que lograr.
class ChallengeDef {
  const ChallengeDef({
    required this.id,
    required this.title,
    required this.metric,
    required this.target,
    required this.reward,
  });

  final String id;
  final String title;
  final ChallengeMetric metric;
  final int target;

  /// Diamantes que se cobran al reclamarlo (10-50).
  final int reward;

  bool get isMax => metric == ChallengeMetric.score;
}

/// Reserva de desafíos. Cada día se eligen tres, con métricas distintas.
const List<ChallengeDef> kChallengePool = [
  ChallengeDef(
    id: 'gems30',
    title: 'Juntá 30 diamantes',
    metric: ChallengeMetric.diamonds,
    target: 30,
    reward: 15,
  ),
  ChallengeDef(
    id: 'gems80',
    title: 'Juntá 80 diamantes',
    metric: ChallengeMetric.diamonds,
    target: 80,
    reward: 40,
  ),
  ChallengeDef(
    id: 'score800',
    title: 'Llegá a 800 puntos en una partida',
    metric: ChallengeMetric.score,
    target: 800,
    reward: 25,
  ),
  ChallengeDef(
    id: 'score2000',
    title: 'Llegá a 2000 puntos en una partida',
    metric: ChallengeMetric.score,
    target: 2000,
    reward: 50,
  ),
  ChallengeDef(
    id: 'jumps25',
    title: 'Saltá 25 veces',
    metric: ChallengeMetric.jumps,
    target: 25,
    reward: 10,
  ),
  ChallengeDef(
    id: 'rolls15',
    title: 'Deslizate 15 veces',
    metric: ChallengeMetric.rolls,
    target: 15,
    reward: 10,
  ),
  ChallengeDef(
    id: 'runs3',
    title: 'Jugá 3 partidas',
    metric: ChallengeMetric.runs,
    target: 3,
    reward: 20,
  ),
  ChallengeDef(
    id: 'powerups3',
    title: 'Agarrá 3 power-ups',
    metric: ChallengeMetric.powerUps,
    target: 3,
    reward: 30,
  ),
];

const int kDailyChallengeCount = 3;

/// Clave estable del día (calendario local): `2026-10-03`.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Los desafíos de un día: mismos para todo el día (y reproducibles en tests),
/// con una métrica distinta cada uno.
List<ChallengeDef> pickDailyChallenges(DateTime day) {
  final seed = day.year * 10000 + day.month * 100 + day.day;
  final shuffled = List<ChallengeDef>.of(kChallengePool)
    ..shuffle(Random(seed));
  final picked = <ChallengeDef>[];
  for (final c in shuffled) {
    if (picked.any((p) => p.metric == c.metric)) continue;
    picked.add(c);
    if (picked.length == kDailyChallengeCount) break;
  }
  return picked;
}

/// Hito de puntaje: se cobra una sola vez, la primera vez que se alcanza.
class ScoreMilestone {
  const ScoreMilestone(this.score, this.reward);

  final int score;
  final int reward;
}

const List<ScoreMilestone> kMilestones = [
  ScoreMilestone(500, 5),
  ScoreMilestone(1000, 10),
  ScoreMilestone(2500, 20),
  ScoreMilestone(5000, 40),
  ScoreMilestone(10000, 80),
];

/// Mejora comprable con diamantes. [costs] tiene un precio por nivel.
class UpgradeDef {
  const UpgradeDef({
    required this.id,
    required this.title,
    required this.description,
    required this.costs,
  });

  final String id;
  final String title;
  final String description;
  final List<int> costs;

  int get maxLevel => costs.length;
}

class UpgradeIds {
  static const startShield = 'startShield';
  static const magnet = 'magnet';
  static const multiplier = 'multiplier';
}

const List<UpgradeDef> kUpgrades = [
  UpgradeDef(
    id: UpgradeIds.startShield,
    title: 'Escudo inicial',
    description: 'Cada partida arranca con el escudo puesto',
    costs: [60],
  ),
  UpgradeDef(
    id: UpgradeIds.magnet,
    title: 'Imán duradero',
    description: '+2 s de imán por nivel',
    costs: [40, 80, 120],
  ),
  UpgradeDef(
    id: UpgradeIds.multiplier,
    title: 'Multiplicador duradero',
    description: '+2 s de x2 por nivel',
    costs: [50, 100, 150],
  ),
];

/// Premio o aviso que la pantalla muestra como cartelito.
class RewardEvent {
  const RewardEvent({
    required this.id,
    required this.title,
    required this.diamonds,
  });

  /// Cambia en cada evento (aunque el texto se repita) para animar de nuevo.
  final int id;
  final String title;

  /// 0 = solo aviso (p. ej. "desafío completado").
  final int diamonds;
}
