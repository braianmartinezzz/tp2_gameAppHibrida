import 'dart:async';
import 'package:flutter/material.dart';

/// Publicidad simulada tipo modal con countdown y formato de anuncio.
/// Se muestra cada vez que se reinicia la partida (requisito de la consigna).
Future<void> showAdModal(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _AdModalContent(),
  );
}

class _AdModalContent extends StatefulWidget {
  const _AdModalContent();

  @override
  State<_AdModalContent> createState() => _AdModalContentState();
}

class _AdModalContentState extends State<_AdModalContent> {
  int _secondsLeft = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() {
        _secondsLeft = (_secondsLeft - 1).clamp(0, 3);
      });
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canClose = _secondsLeft <= 0;
    return AlertDialog(
      title: const Text('Anuncio simulado'),
      content: SizedBox(
        height: 120,
        child: Center(
          child: Icon(Icons.smart_display_outlined, size: 48),
        ),
      ),
      actions: [
        TextButton(
          onPressed: canClose ? () => Navigator.of(context).pop() : null,
          child: Text(canClose ? 'Cerrar' : 'Cerrar (${_secondsLeft}s)'),
        ),
      ],
    );
  }
}
