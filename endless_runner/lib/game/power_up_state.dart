import 'power_up_component.dart';

/// Estado de los power-ups activos.
///
/// Vive fuera del árbol de componentes (es puro estado), de modo que se puede
/// probar sin inciar la partida y el juego solo lo consume:
///
///  - [shield] es una carga única que se gasta en [absorbHit];
///  - [magnetTimer] y [multiplierTimer] se descuentan solos con el tiempo;
///  - [invulnerableTimer] es el respiro que queda después de cada golpe
///    absorbido para que el obstáculo siguiente no te mate en el mismo frame.
class PowerUpState {
  PowerUpState({
    this.magnetDuration = 6,
    this.multiplierDuration = 8,
    this.invulnerableDuration = 1.2,
  });

  /// Duración del imán, en segundos.
  final double magnetDuration;

  /// Duración del multiplicador, en segundos.
  final double multiplierDuration;

  /// Respiro de invulnerabilidad al absorber un golpe, en segundos.
  final double invulnerableDuration;

  bool shield = false;
  double magnetTimer = 0;
  double multiplierTimer = 0;
  double invulnerableTimer = 0;

  bool get hasShield => shield;
  bool get isMagnetActive => magnetTimer > 0;
  bool get isMultiplierActive => multiplierTimer > 0;
  bool get isInvulnerable => invulnerableTimer > 0;

  /// Factor aplicado al score mientras dure el multiplicador.
  double get scoreMultiplier => isMultiplierActive ? 2 : 1;

  /// Aplica un power-up. Devuelve `false` si no hacía falta (escudo ya
  /// activo), así el juego puede dejar el ítem volando en lugar de tragárselo.
  bool apply(PowerUpKind kind) {
    switch (kind) {
      case PowerUpKind.shield:
        if (shield) return false;
        shield = true;
      case PowerUpKind.magnet:
        magnetTimer = magnetDuration;
      case PowerUpKind.multiplier:
        multiplierTimer = multiplierDuration;
    }
    return true;
  }

  /// Intenta absorber un golpe con el escudo.
  ///
  /// `true` = el escudo se rompió y el golpe no cuenta (queda invulnerabilidad
  /// de [invulnerableDuration]).
  bool absorbHit() {
    if (!shield) return false;
    shield = false;
    invulnerableTimer = invulnerableDuration;
    return true;
  }

  /// Respiro de invulnerabilidad, p.ej. cuando el golpe se paga con diamantes.
  void grantInvulnerability() {
    invulnerableTimer = invulnerableDuration;
  }

  /// Descuenta los temporizadores. Nunca bajan de 0.
  void update(double dt) {
    if (magnetTimer > 0) {
      magnetTimer -= dt;
      if (magnetTimer < 0) magnetTimer = 0;
    }
    if (multiplierTimer > 0) {
      multiplierTimer -= dt;
      if (multiplierTimer < 0) multiplierTimer = 0;
    }
    if (invulnerableTimer > 0) {
      invulnerableTimer -= dt;
      if (invulnerableTimer < 0) invulnerableTimer = 0;
    }
  }

  /// Vuelve a cero (reinicio de partida).
  void reset() {
    shield = false;
    magnetTimer = 0;
    multiplierTimer = 0;
    invulnerableTimer = 0;
  }
}
