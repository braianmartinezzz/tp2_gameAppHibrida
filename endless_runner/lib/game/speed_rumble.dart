import 'dart:math';
import 'dart:ui';

/// Temblor de cámara por velocidad: a medida que el mundo acelera, la imagen
/// vibra apenas (sobre todo en vertical, como la carretera bajo las ruedas).
///
/// Es puramente visual: se aplica como traslación del canvas en
/// `RunnerGame.render`, así que no toca hitboxes ni lógica. Funciones puras y
/// deterministas (dependen solo del tiempo y la velocidad) para poder
/// testearlas sin motor.
abstract final class SpeedRumble {
  /// Velocidad (px/s) por debajo de la cual no hay temblor: el arranque.
  static const double baseSpeed = 260;

  /// Velocidad a la que el temblor llega a su máximo (~63 s de partida, ya
  /// que la dificultad suma 6 px/s por segundo).
  static const double fullSpeed = 640;

  /// Desplazamiento máximo en px. Chico a propósito: se siente, no marea.
  static const double maxAmplitude = 1.8;

  /// 0..1: crece despacio al principio (curva t^1.5) y se queda en 1.
  static double intensity(double speed) {
    final t = ((speed - baseSpeed) / (fullSpeed - baseSpeed)).clamp(0.0, 1.0);
    return pow(t, 1.5).toDouble();
  }

  /// Amplitud máxima del frame (cota de [offsetAt] en cada eje).
  static double amplitude(double speed) => maxAmplitude * intensity(speed);

  /// Desplazamiento de cámara para el instante [time] (s) a [speed] (px/s).
  /// Dos senos de frecuencias incomensurables en vertical (rugosidad del
  /// asfalto) y uno más lento en horizontal (el corredor "cabecea").
  static Offset offsetAt(double time, double speed) {
    final amp = amplitude(speed);
    if (amp <= 0) return Offset.zero;
    final dy = 0.6 * sin(time * 31) + 0.4 * sin(time * 47 + 1.3);
    final dx = 0.5 * sin(time * 23 + 0.7);
    return Offset(dx * amp, dy * amp);
  }
}
