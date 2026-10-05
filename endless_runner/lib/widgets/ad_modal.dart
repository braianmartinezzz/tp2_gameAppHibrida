import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../state/game_state.dart';
import '../theme/app_theme.dart';
import 'ad_video_cache.dart';

/// Anuncio que corta el juego (al reiniciar la partida). La cuenta Pro no lo
/// ve: es el beneficio de pagar. Los anuncios voluntarios con premio (revivir,
/// +diamantes) usan [showAdModal] directo, porque el jugador los elige.
Future<void> showInterstitialAd(BuildContext context, GameState state) async {
  if (state.isPro) return;
  await showAdModal(context);
}

/// Publicidad simulada tipo modal con countdown y formato de anuncio.
/// Se muestra cada vez que se reinicia la partida (requisito de la consigna).
///
/// Devuelve `true` si el anuncio se vio completo (se cerró con el botón una
/// vez terminado el countdown) y `false` si se salió antes (p. ej. con el
/// botón "atrás"): los anuncios con premio solo pagan en el primer caso.
///
/// Con [rewarded] el anuncio exige más tiempo de visto antes de poder
/// cerrarse (los de premio: revivir, +diamantes). Reproduce uno de los videos
/// de `assets/video/`, que la app viene **precargando** en segundo plano
/// ([AdVideoCache]) para que el modal no abra vacío; si el video no se puede
/// usar (tests, plataforma sin plugin, archivo roto) cae al anuncio simulado
/// de siempre, con cuenta de 3 s.
Future<bool> showAdModal(
  BuildContext context, {
  String? hint,
  String closeLabel = 'Cerrar',
  bool rewarded = false,
}) async {
  final watched = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Anuncio',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => SafeArea(
      child: _AdModalContent(
        hint: hint,
        closeLabel: closeLabel,
        rewarded: rewarded,
      ),
    ),
    // Entrada: fundido + escala suave; salida: el mismo recorrido a la inversa.
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return watched ?? false;
}

class _AdModalContent extends StatefulWidget {
  const _AdModalContent({
    this.hint,
    this.closeLabel = 'Cerrar',
    this.rewarded = false,
  });

  final bool rewarded;

  /// Texto opcional bajo la barra de progreso (qué se gana al terminar).
  final String? hint;
  final String closeLabel;

  @override
  State<_AdModalContent> createState() => _AdModalContentState();
}

class _AdModalContentState extends State<_AdModalContent> {
  /// Cuenta del anuncio simulado (sin video).
  static const int _fallbackSeconds = 3;

  /// Cuánto se espera al video precargado antes de rendirse con ESTE anuncio
  /// (la carga no se corta: queda lista para el próximo).
  static const Duration _loadTimeout = Duration(seconds: 6);

  /// Segundos de video que hay que ver antes de poder cerrar. Los videos duran
  /// entre 25 y 90 s: obligar a verlos enteros sería insoportable, así que se
  /// pueden cerrar a los 5 s (10 s en los anuncios con premio).
  static const int _skipAfter = 5;
  static const int _skipAfterRewarded = 10;

  int _total = _fallbackSeconds;
  int _secondsLeft = _fallbackSeconds;

  /// Segundos que ya pasaron desde que abrió el anuncio: cuando el video
  /// llega tarde sirve para medir cuánto del video todavía falta ver, sin que
  /// el anuncio termine durando más de lo que prometía.
  int _elapsed = 0;

  Timer? _timer;
  VideoPlayerController? _video;
  bool _videoReady = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _loadVideo();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _elapsed += 1;
        _secondsLeft = (_secondsLeft - 1).clamp(0, _total);
      });
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  /// Pide el video que la app viene precargando ([AdVideoCache.ensureLoaded]).
  /// Si no está listo a tiempo, este anuncio sigue siendo el simulado y la
  /// carga sigue en background para el siguiente: un video que llega tarde ya
  /// no se descarta (antes, si tardaba más que la cuenta de 3 s, el video se
  /// tiraba y el anuncio quedaba simulado entero).
  Future<void> _loadVideo() async {
    final controller = await AdVideoCache.ensureLoaded().timeout(
      _loadTimeout,
      onTimeout: () => null,
    );
    if (!mounted || controller == null) return;

    final skipAfter = widget.rewarded ? _skipAfterRewarded : _skipAfter;
    final seconds = controller.value.duration.inSeconds;
    setState(() {
      _video = controller;
      _videoReady = true;
      final wanted = max(1, min(skipAfter, seconds));
      _total = max(_total, wanted);
      // La cuenta se mide contra lo que ya pasó: el anuncio termina a los
      // `wanted` segundos de abierto (o antes, si el video llegó tarde) y el
      // video siempre muestra al menos lo que falta ver. Nunca se alarga.
      _secondsLeft = max(_secondsLeft, wanted - _elapsed);
    });
    _startTimer();
    await controller.play();
  }

  @override
  void dispose() {
    _timer?.cancel();
    // El cache descarta el controller (solo existía para este anuncio) y
    // aprovecha para precargar otro video, distinto, para el próximo.
    if (_video != null) AdVideoCache.release();
    super.dispose();
  }

  /// Espera de la carga: póster del video que se está precargando, con la
  /// etiqueta de publicidad y el rótulo de carga encima (si el póster no
  /// está, queda el degradé de siempre por debajo).
  ///
  /// Sin spinner giratorio: los tests cierran el anuncio con `pumpAndSettle`
  /// y una animación infinita los dejaría esperando.
  Widget _buildLoading() {
    final poster = AdVideoCache.currentPoster;
    return Container(
      height: 140,
      width: double.maxFinite,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B8A), Color(0xFFFFB020)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (poster != null)
            Image.asset(
              poster,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'PUBLICIDAD',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.hourglass_top_rounded,
                        size: 14, color: Colors.white.withValues(alpha: 0.9)),
                    const SizedBox(width: 6),
                    const Text(
                      'Cargando anuncio…',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Video del anuncio con la etiqueta de publicidad encima.
  Widget _buildVideo(BuildContext context) {
    final controller = _video!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoPlayer(controller),
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'PUBLICIDAD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canClose = _secondsLeft <= 0;
    final progress = (_total - _secondsLeft) / _total;

    // Hasta que termina el countdown el anuncio no se puede cerrar, ni con el
    // botón "atrás": así un premio nunca se cobra sin verlo.
    return PopScope(
      canPop: canClose,
      child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
      actionsPadding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
      title: Row(
        children: [
          Icon(Icons.campaign_rounded,
              color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          const Text(
            'Anuncio simulado',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mientras el video precargado no está listo: póster del video (o
          // el degradé de siempre si no está) con el rótulo de carga.
          if (_videoReady)
            _buildVideo(context)
          else
            _buildLoading(),
          const SizedBox(height: 14),
          // Barra de progreso: se llena a medida que corre el countdown.
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 900),
              builder: (_, value, __) => LinearProgressIndicator(
                value: value,
                minHeight: 8,
                color: AppColors.play,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          if (widget.hint != null) ...[
            const SizedBox(height: 12),
            Text(
              widget.hint!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: canClose ? () => Navigator.of(context).pop(true) : null,
            child: Text(
              canClose
                  ? widget.closeLabel
                  : '${widget.closeLabel} (${_secondsLeft}s)',
            ),
          ),
        ),
      ],
    ),
    );
  }
}
