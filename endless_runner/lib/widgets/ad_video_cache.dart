import 'dart:async';
import 'dart:math';

import 'package:video_player/video_player.dart';

/// Videos de los anuncios (están en `assets/video/`).
const List<String> kAdVideos = [
  'assets/video/keep_thinking_with_claude.mp4',
  'assets/video/lucchetti.mp4',
  'assets/video/sports_forever.mp4',
];

/// Póster (primer frame) de un video: tapa la espera de la carga con algo con
/// forma de anuncio en vez de un hueco vacío.
String adPosterFor(String video) =>
    video.replaceFirst(RegExp(r'\.mp4$'), '.jpg');

/// Precarga del video de los anuncios.
///
/// El `initialize()` de un MP4 de varios MB es lo que hacía que el modal
/// abriera "vacío" (o, si tardaba más que la cuenta de 3 s, que el video se
/// descartara y el anuncio quedara simulado entero). Para que eso no pase la
/// app viene cargando el próximo video en segundo plano: al arrancar y después
/// de cada anuncio, así el modal lo encuentra listo.
///
/// Todo es defensivo: en tests o en plataformas sin plugin la inicialización
/// falla, devuelve `null` y el anuncio sigue siendo el simulado de siempre.
class AdVideoCache {
  AdVideoCache._();

  /// Controller listo para mostrar: inicializado y todavía sin reproducir.
  static VideoPlayerController? _ready;

  /// Carga en curso: un solo `initialize()` a la vez, compartido por todos.
  static Future<VideoPlayerController?>? _loading;

  /// Último video mostrado (y el que se está cargando ahora): el siguiente
  /// elige otro y el póster sabe qué imagen mostrar mientras carga.
  static int _lastVideo = -1;
  static int _index = -1;

  /// Controller inicializado, o `null` si no se pudo cargar.
  static Future<VideoPlayerController?> ensureLoaded() {
    final ready = _ready;
    if (ready != null && ready.value.isInitialized) {
      return Future<VideoPlayerController?>.value(ready);
    }
    return _loading ??= _load();
  }

  /// Empieza a cargar el próximo video sin esperar: al arrancar la app y
  /// apenas se cierra cada anuncio, para que el siguiente encuentre listo.
  static void warmUp() {
    try {
      unawaited(ensureLoaded());
    } catch (_) {
      // Plataforma sin plugin: el anuncio simulado se encarga.
    }
  }

  /// El modal ya no lo usa: libera el controller (que solo existe para ese
  /// anuncio) y arranca la carga del siguiente, con otro video.
  static void release() {
    final controller = _ready;
    _ready = null;
    if (controller != null) {
      try {
        unawaited(controller.dispose());
      } catch (_) {
        // Ya descargado: no hay nada que limpiar.
      }
    }
    warmUp();
  }

  /// Póster del video que se está cargando (o el que ya quedó listo), para
  /// mostrarlo en el modal mientras no hay frame decodificado.
  static String? get currentPoster {
    final index = _index;
    return index < 0 ? null : adPosterFor(kAdVideos[index]);
  }

  static Future<VideoPlayerController?> _load() async {
    try {
      var index = Random().nextInt(kAdVideos.length);
      if (index == _lastVideo) index = (index + 1) % kAdVideos.length;
      _index = index;
      final controller = VideoPlayerController.asset(kAdVideos[index]);
      await controller.initialize();
      _lastVideo = index;
      _ready = controller;
      return controller;
    } catch (_) {
      return null;
    } finally {
      _loading = null;
    }
  }
}
