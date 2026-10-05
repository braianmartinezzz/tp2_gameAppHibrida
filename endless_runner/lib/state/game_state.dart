import 'dart:math';

import 'package:flutter/material.dart';

import 'rewards.dart';
import 'settings_store.dart';

/// Estado global simulado del jugador y de la partida.
/// Se pasa por referencia al FlameGame para que el juego pueda
/// leer/escribir score y diamantes, y la UI de Flutter (header,
/// botonera, modales) reaccione a los cambios sin acoplarse al motor.
///
/// Dos recursos separados:
///  - **Diamantes** ([diamonds]): la moneda del juego. Se gastan en las mejoras
///    de la tienda. Se ganan recolectando (+1 a +5), con desafíos diarios,
///    anuncios voluntarios (+5 a +20) e hitos de puntaje.
///  - **Vidas** ([lives]): los corazones de la partida. Arrancan en
///    [maxLives]; cada choque sin escudo resta una y con cero termina la
///    partida.
class GameState {
  /// [store] persiste el progreso. Sin store (tests, previews) todo vive en
  /// memoria. [clock] y [random] se inyectan para poder probar los desafíos
  /// diarios y los anuncios.
  GameState({SettingsStore? store, DateTime Function()? clock, Random? random})
      : _store = store,
        _clock = clock ?? DateTime.now,
        _random = random ?? Random() {
    _ensureToday();
  }

  final SettingsStore? _store;
  final DateTime Function() _clock;
  final Random _random;

  /// Rango de la sensibilidad de los gestos: 1.0 es el comportamiento original.
  static const double minSensitivity = 0.5;
  static const double maxSensitivity = 2.0;
  static const double defaultSensitivity = 1.0;

  /// Corazones al empezar cada partida (cuenta basic).
  static const int maxLives = 2;

  /// Corazones al empezar cada partida con cuenta Pro: uno extra.
  static const int proMaxLives = 3;

  /// Precio (simulado) del pase a Pro, pago único.
  static const String proPrice = '\$2.99';

  /// Anuncios voluntarios con premio por día.
  static const int maxAdsPerDay = 5;

  final ValueNotifier<String> username = ValueNotifier('braian_123');
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> diamonds = ValueNotifier(85);
  final ValueNotifier<String> accountType =
      ValueNotifier('basic'); // 'basic' | 'pro'
  final ValueNotifier<bool> isGameOver = ValueNotifier(false);

  /// Tema elegido por el usuario. `system` (default) sigue al sistema
  /// operativo: es el único estado que el canvas no puede resolver solo,
  /// porque Flame no tiene [BuildContext].
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  /// Brillo del sistema, espejado desde [WidgetsBindingObserver]
  /// (`didChangePlatformBrightness`) para que el juego pueda resolver
  /// [isDark] sin contexto. Arranca en oscuro (coincide con el look por
  /// defecto del juego).
  final ValueNotifier<Brightness> platformBrightness =
      ValueNotifier(Brightness.dark);

  /// Modo efectivo: resuelve `system` contra el brillo del sistema. Lo usan
  /// el canvas de Flame y cualquier widget que necesite saber "¿es de noche?"
  /// sin construir un árbol nuevo.
  bool get isDark => themeMode.value == ThemeMode.system
      ? platformBrightness.value == Brightness.dark
      : themeMode.value == ThemeMode.dark;

  /// Brillo efectivo para la UI de Flutter. `MaterialApp` resuelve `system`
  /// solo, pero sirve para widgets fuera del árbol (barra de estado, etc).
  Brightness get effectiveBrightness =>
      isDark ? Brightness.dark : Brightness.light;

  /// Corazones que le quedan al jugador en la partida actual.
  final ValueNotifier<int> lives = ValueNotifier(maxLives);

  /// true mientras la partida está pausada por el usuario (overlay de pausa).
  final ValueNotifier<bool> isPaused = ValueNotifier(false);

  /// true si el usuario ya completó (o salteó) el tutorial de gestos.
  final ValueNotifier<bool> tutorialSeen = ValueNotifier(false);

  /// Música de la partida prendida (Ajustes). Es el único que decide si
  /// [GameMusic] suena o no: el interruptor corta al instante y se guarda con
  /// el resto del progreso.
  final ValueNotifier<bool> musicEnabled = ValueNotifier(true);

  /// Multiplicador de sensibilidad de los gestos: valores altos aceptan
  /// deslizamientos más cortos.
  final ValueNotifier<double> swipeSensitivity =
      ValueNotifier(defaultSensitivity);

  /// Mejor puntaje de la sesión. Vive en memoria (como todo el estado
  /// simulado de este prototipo): sobrevive a los reinicios de partida, no a
  /// cerrar la app.
  final ValueNotifier<int> bestScore = ValueNotifier(0);

  /// true si la partida que acaba de terminar superó el récord anterior.
  final ValueNotifier<bool> isNewRecord = ValueNotifier(false);

  /// Diamantes ganados en la partida actual (distinto de [diamonds], que es
  /// la billetera: se gasta en las mejoras de la tienda).
  final ValueNotifier<int> runDiamonds = ValueNotifier(0);

  bool get isPro => accountType.value == 'pro';

  /// Corazones con los que arranca cada partida según el tipo de cuenta.
  int get startingLives => isPro ? proMaxLives : maxLives;

  /// Mejora la cuenta a Pro (compra simulada, pago único). Beneficios: sin
  /// anuncios y un corazón extra por partida. Si hay una partida en curso, el
  /// corazón extra se suma al instante. Devuelve `false` si ya era Pro.
  bool upgradeToPro() {
    if (isPro) return false;
    accountType.value = 'pro';
    if (!isGameOver.value && lives.value > 0) {
      lives.value = min(proMaxLives, lives.value + 1);
    }
    save();
    return true;
  }

  // --- Revivir ---------------------------------------------------------------

  /// true si en esta partida ya se usó el revivir (una sola vez por partida).
  bool revivedThisRun = false;

  /// Récord vigente antes de que [finishRun] lo actualizara: se restaura al
  /// revivir para que un nuevo récord no se "celebre" dos veces.
  int _bestBeforeFinish = 0;

  /// true si la partida terminó y todavía se puede ofrecer revivir.
  bool get canRevive => isGameOver.value && !revivedThisRun;

  /// Reanuda la partida terminada con una sola vida. `false` si no
  /// corresponde (no terminó, o ya se revivió en esta partida).
  bool revive() {
    if (!canRevive) return false;
    revivedThisRun = true;
    bestScore.value = _bestBeforeFinish;
    isNewRecord.value = false;
    lives.value = 1;
    isGameOver.value = false;
    return true;
  }

  // --- Mejoras ---------------------------------------------------------------

  /// Nivel comprado de cada mejora (id -> nivel). Se reemplaza el mapa entero
  /// en cada compra para que los oyentes se enteren.
  final ValueNotifier<Map<String, int>> upgradeLevels = ValueNotifier(const {});

  int upgradeLevel(String id) => upgradeLevels.value[id] ?? 0;

  /// Compra el siguiente nivel de [def] con diamantes. `false` si ya está al
  /// máximo o no alcanzan.
  bool buyUpgrade(UpgradeDef def) {
    final level = upgradeLevel(def.id);
    if (level >= def.maxLevel) return false;
    if (!spendDiamonds(def.costs[level])) return false;
    upgradeLevels.value = {...upgradeLevels.value, def.id: level + 1};
    save();
    return true;
  }

  // --- Hitos, desafíos y anuncios -------------------------------------------

  /// Hitos de puntaje ya cobrados (por puntaje).
  final Set<int> claimedMilestones = {};

  /// Se incrementa cada vez que cambia algo de desafíos/hitos/anuncios: la
  /// pantalla de premios se redibuja con esto.
  final ValueNotifier<int> rewardsTick = ValueNotifier(0);

  /// Desafíos completados y todavía sin reclamar (para el globito de la
  /// botonera).
  final ValueNotifier<int> claimable = ValueNotifier(0);

  /// Último premio/aviso para mostrar como cartelito.
  final ValueNotifier<RewardEvent?> rewardEvent = ValueNotifier(null);
  int _eventId = 0;

  String _dayKey = '';
  List<ChallengeDef> _challenges = const [];
  final Map<String, int> _progress = {};
  final Set<String> _claimedChallenges = {};
  int _adsToday = 0;

  /// Desafíos de hoy (se renuevan solos al cambiar el día).
  List<ChallengeDef> get challenges {
    _ensureToday();
    return _challenges;
  }

  int challengeProgress(ChallengeDef c) => min(c.target, _progress[c.id] ?? 0);

  bool isChallengeComplete(ChallengeDef c) => challengeProgress(c) >= c.target;

  bool isChallengeClaimed(ChallengeDef c) => _claimedChallenges.contains(c.id);

  int get adsLeftToday {
    _ensureToday();
    return max(0, maxAdsPerDay - _adsToday);
  }

  void _ensureToday() {
    final now = _clock();
    final key = dayKey(now);
    if (key == _dayKey) return;
    _dayKey = key;
    _challenges = pickDailyChallenges(now);
    _progress.clear();
    _claimedChallenges.clear();
    _adsToday = 0;
    _notifyRewards();
  }

  void _notifyRewards() {
    claimable.value = _challenges
        .where((c) => isChallengeComplete(c) && !isChallengeClaimed(c))
        .length;
    rewardsTick.value++;
  }

  void _emit(String title, {int diamonds = 0}) {
    rewardEvent.value =
        RewardEvent(id: ++_eventId, title: title, diamonds: diamonds);
  }

  /// Avanza los desafíos acumulativos (saltos, deslizamientos, partidas,
  /// power-ups, diamantes).
  void recordEvent(ChallengeMetric metric, [int amount = 1]) {
    _ensureToday();
    var completedNow = false;
    for (final c in _challenges) {
      if (c.metric != metric || c.isMax || isChallengeComplete(c)) continue;
      _progress[c.id] = (_progress[c.id] ?? 0) + amount;
      if (isChallengeComplete(c)) {
        completedNow = true;
        _emit('¡Desafío cumplido! ${c.title}');
      }
    }
    if (completedNow) _notifyRewards();
  }

  void _recordScoreMax(int value) {
    var completedNow = false;
    for (final c in _challenges) {
      if (!c.isMax || isChallengeComplete(c)) continue;
      _progress[c.id] = max(_progress[c.id] ?? 0, value);
      if (isChallengeComplete(c)) {
        completedNow = true;
        _emit('¡Desafío cumplido! ${c.title}');
      }
    }
    if (completedNow) _notifyRewards();
  }

  /// Cobra un desafío completado. `false` si no corresponde.
  bool claimChallenge(ChallengeDef c) {
    _ensureToday();
    if (!isChallengeComplete(c) || isChallengeClaimed(c)) return false;
    _claimedChallenges.add(c.id);
    diamonds.value += c.reward;
    _notifyRewards();
    save();
    return true;
  }

  void _checkMilestones() {
    for (final m in kMilestones) {
      if (score.value < m.score || !claimedMilestones.add(m.score)) continue;
      diamonds.value += m.reward;
      _emit('¡Hito de ${m.score} puntos!', diamonds: m.reward);
      _notifyRewards();
      save();
    }
  }

  /// Premio de un anuncio voluntario: 5 a 20 diamantes. Devuelve lo ganado, o
  /// 0 si ya se agotó el cupo diario.
  int grantAdReward() {
    _ensureToday();
    if (_adsToday >= maxAdsPerDay) return 0;
    _adsToday++;
    final amount = 5 + _random.nextInt(16);
    diamonds.value += amount;
    _notifyRewards();
    save();
    return amount;
  }

  // --- Partida ---------------------------------------------------------------

  void addScore(int points) {
    score.value += points;
    if (isGameOver.value) return;
    _recordScoreMax(score.value);
    _checkMilestones();
  }

  void addDiamonds(int amount) {
    diamonds.value += amount;
    save();
  }

  /// Diamante(s) recolectado(s) en el corredor ([value] de 1 a 5): suma a la
  /// billetera y al resumen de la partida. No guarda en disco por cada
  /// moneda: se guarda al terminar o pausar.
  void collectDiamond([int value = 1]) {
    diamonds.value += value;
    runDiamonds.value += value;
    recordEvent(ChallengeMetric.diamonds, value);
  }

  /// Resta una vida. Devuelve las que quedan (0 = fin de la partida).
  int loseLife() {
    lives.value = max(0, lives.value - 1);
    return lives.value;
  }

  /// Termina la partida: congela el resultado y actualiza el récord.
  ///
  /// Es la única puerta de entrada a [isGameOver]: así el resumen nunca ve un
  /// récord desactualizado, y un segundo llamado (colisión doble, test raro)
  /// no pisa lo que ya se celebró.
  void finishRun() {
    if (isGameOver.value) return;
    _bestBeforeFinish = bestScore.value;
    isNewRecord.value = score.value > bestScore.value;
    if (isNewRecord.value) bestScore.value = score.value;
    isGameOver.value = true;
    // Una partida revivida cuenta una sola vez para los desafíos.
    if (!revivedThisRun) recordEvent(ChallengeMetric.runs);
    save();
  }

  /// Devuelve true si pudo pagar.
  bool spendDiamonds(int amount) {
    if (diamonds.value < amount) return false;
    diamonds.value -= amount;
    save();
    return true;
  }

  /// Alterna basic/pro sin pasar por la compra (atajo para pruebas).
  void toggleAccountType() {
    accountType.value = isPro ? 'basic' : 'pro';
  }

  /// Cicla el tema: **Auto → Claro → Oscuro → Auto**.
  ///
  /// Se guarda en cuanto cambia para que un cierre de la app no pierda la
  /// preferencia.
  void cycleTheme() {
    themeMode.value = switch (themeMode.value) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    save();
  }

  // --- Persistencia ----------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'tutorialSeen': tutorialSeen.value,
        'music': musicEnabled.value,
        'swipeSensitivity': swipeSensitivity.value,
        'theme': switch (themeMode.value) {
          ThemeMode.system => 'system',
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
        },
        'diamonds': diamonds.value,
        'pro': isPro,
        'upgrades': Map<String, int>.of(upgradeLevels.value),
        'milestones': claimedMilestones.toList(),
        'daily': {
          'day': _dayKey,
          'progress': Map<String, int>.of(_progress),
          'claimed': _claimedChallenges.toList(),
          'ads': _adsToday,
        },
      };

  void _applyJson(Map<String, dynamic> json) {
    tutorialSeen.value = json['tutorialSeen'] == true;
    // Música guardada. Saves viejos no traen la clave: se respeta el default
    // (prendida) y no se pisa nada.
    final music = json['music'];
    if (music is bool) musicEnabled.value = music;
    // Tema guardado. Saves viejos no traen la clave: se respeta el default
    // (system) y no se pisa nada.
    final savedTheme = json['theme'];
    if (savedTheme is String) {
      themeMode.value = switch (savedTheme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => themeMode.value,
      };
    }
    final sens = json['swipeSensitivity'];
    if (sens is num) {
      swipeSensitivity.value =
          sens.toDouble().clamp(minSensitivity, maxSensitivity).toDouble();
    }
    // Cuenta Pro guardada. Saves viejos no traen la clave: sigue basic.
    if (json['pro'] == true) {
      accountType.value = 'pro';
      lives.value = proMaxLives;
    }
    final gems = json['diamonds'];
    if (gems is int && gems >= 0) diamonds.value = gems;

    final upgrades = json['upgrades'];
    if (upgrades is Map) {
      upgradeLevels.value = {
        for (final def in kUpgrades)
          if (upgrades[def.id] is int)
            def.id: (upgrades[def.id] as int).clamp(0, def.maxLevel).toInt(),
      };
    }
    final milestones = json['milestones'];
    if (milestones is List) {
      claimedMilestones
        ..clear()
        ..addAll(milestones.whereType<int>());
    }

    // Los desafíos guardados solo valen si son de hoy; si no, quedan los
    // recién sorteados.
    final daily = json['daily'];
    if (daily is Map && daily['day'] == dayKey(_clock())) {
      _dayKey = daily['day'] as String;
      _challenges = pickDailyChallenges(_clock());
      _progress.clear();
      final progress = daily['progress'];
      if (progress is Map) {
        progress.forEach((k, v) {
          if (k is String && v is int) _progress[k] = v;
        });
      }
      _claimedChallenges
        ..clear()
        ..addAll((daily['claimed'] as List? ?? const []).whereType<String>());
      _adsToday = daily['ads'] is int ? daily['ads'] as int : 0;
    }
    _notifyRewards();
  }

  /// Carga el progreso guardado. Si falla (plugin no disponible, disco), la
  /// app sigue con los valores por defecto: no es crítico.
  Future<void> loadSettings() async {
    final store = _store;
    if (store == null) return;
    try {
      final saved = await store.load();
      if (saved != null) _applyJson(saved);
    } catch (_) {}
  }

  /// Guarda el progreso. Sin store no hace nada; los errores se ignoran.
  void save() {
    final store = _store;
    if (store == null) return;
    store.save(toJson()).catchError((Object _) {});
  }

  void markTutorialSeen() {
    if (tutorialSeen.value) return;
    tutorialSeen.value = true;
    save();
  }

  void setSwipeSensitivity(double value) {
    swipeSensitivity.value =
        value.clamp(minSensitivity, maxSensitivity).toDouble();
    save();
  }

  /// Prende o apaga la música de la partida y lo persiste.
  void setMusicEnabled(bool value) {
    if (musicEnabled.value == value) return;
    musicEnabled.value = value;
    save();
  }

  void resetRun() {
    isPaused.value = false;
    score.value = 0;
    runDiamonds.value = 0;
    lives.value = startingLives;
    isNewRecord.value = false;
    revivedThisRun = false;
    isGameOver.value = false;
    // bestScore NO se toca: el récord es lo único que sobrevive a un reinicio.
  }
}
