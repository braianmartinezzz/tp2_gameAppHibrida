import 'dart:math';

import 'package:flutter/material.dart';

import '../audio/game_sfx.dart';
import '../theme/app_theme.dart';

/// Qué se está comprando en [showPurchaseFlow].
class PurchaseItem {
  const PurchaseItem({
    required this.title,
    required this.price,
    required this.icon,
    required this.summary,
    required this.onPaid,
    required this.successTitle,
    this.successSubtitle,
    this.successBody,
    this.accent = AppColors.goldDeep,
    this.onAccent = AppColors.goldInk,
    this.doneLabel = '¡Genial!',
  });

  /// Título de la hoja ("Mejorar a Pro", "500 diamantes").
  final String title;

  /// Precio ficticio tal como se muestra ("$4.99").
  final String price;

  /// Ícono grande de la cabecera (corona, gemas...).
  final Widget icon;

  /// Qué incluye la compra; se muestra antes de pagar.
  final Widget summary;

  /// Se llama una sola vez, cuando el pago se aprueba.
  final VoidCallback onPaid;

  final String successTitle;
  final String? successSubtitle;

  /// Contenido extra de la pantalla de éxito (p. ej. la lista de beneficios).
  final Widget? successBody;

  /// Color del botón de pagar y del botón final.
  final Color accent;
  final Color onAccent;
  final String doneLabel;
}

/// Pregunta de la puerta parental: una suma que un adulto resuelve al
/// instante y un chico que todavía no sabe sumar de a dos cifras, no.
class ParentalQuestion {
  const ParentalQuestion({
    required this.a,
    required this.b,
    required this.options,
  });

  /// Arma una pregunta nueva: dos sumandos de dos cifras y tres opciones
  /// distintas (la correcta y dos cercanas), ya mezcladas.
  factory ParentalQuestion.generate(Random random) {
    final a = 12 + random.nextInt(18); // 12..29
    final b = 13 + random.nextInt(36); // 13..48
    final answer = a + b;
    final options = <int>{answer};
    while (options.length < 3) {
      final delta = 1 + random.nextInt(9); // 1..9
      final wrong = random.nextBool() ? answer + delta : answer - delta;
      if (wrong > 0) options.add(wrong);
    }
    return ParentalQuestion(
      a: a,
      b: b,
      options: options.toList()..shuffle(random),
    );
  }

  final int a;
  final int b;
  final List<int> options;

  int get answer => a + b;
  String get text => '$a + $b';
}

/// Flujo de compra simulada (no se cobra nada): resumen, puerta parental,
/// "procesando" y resultado (éxito o pago rechazado). Lo usan los packs de
/// diamantes, el pack de bienvenida y Pro, para que todas las compras se
/// sientan igual. Devuelve `true` si el pago se aprobó.
///
/// [processingDelay] es lo que dura el "procesando" (los tests lo acortan).
Future<bool> showPurchaseFlow(
  BuildContext context,
  PurchaseItem item, {
  Random? random,
  Duration processingDelay = const Duration(milliseconds: 1400),
}) async {
  GameSfx.instance.play(Sfx.open);
  final paid = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    // Solo se cierra con los botones: así nunca se cancela a medio cobrar.
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (context) => _PurchaseSheet(
      item: item,
      random: random ?? Random(),
      processingDelay: processingDelay,
    ),
  );
  return paid ?? false;
}

enum _Phase { summary, gate, processing, done, failed }

class _PurchaseSheet extends StatefulWidget {
  const _PurchaseSheet({
    required this.item,
    required this.random,
    required this.processingDelay,
  });

  final PurchaseItem item;
  final Random random;
  final Duration processingDelay;

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<_PurchaseSheet> {
  _Phase _phase = _Phase.summary;

  /// Demo: el próximo intento termina en "pago rechazado".
  bool _rejectNext = false;

  /// Evita cobrar dos veces si algo reintenta.
  bool _paid = false;

  late ParentalQuestion _question = ParentalQuestion.generate(widget.random);
  bool _wrongAnswer = false;

  PurchaseItem get item => widget.item;

  void _openGate() {
    setState(() {
      _question = ParentalQuestion.generate(widget.random);
      _wrongAnswer = false;
      _phase = _Phase.gate;
    });
  }

  void _answer(int value) {
    if (value == _question.answer) {
      _pay();
    } else {
      // Respuesta incorrecta: pregunta nueva, para que no valga adivinar.
      setState(() {
        _question = ParentalQuestion.generate(widget.random);
        _wrongAnswer = true;
      });
    }
  }

  Future<void> _pay() async {
    setState(() => _phase = _Phase.processing);
    await Future<void>.delayed(widget.processingDelay);
    if (!mounted) return;
    if (_rejectNext) {
      _rejectNext = false; // el reintento sale bien
      GameSfx.instance.play(Sfx.error);
      setState(() => _phase = _Phase.failed);
      return;
    }
    if (!_paid) {
      _paid = true;
      item.onPaid();
    }
    GameSfx.instance.play(Sfx.buy);
    setState(() => _phase = _Phase.done);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Mientras "se procesa" el pago no se puede salir con "atrás".
      canPop: _phase != _Phase.processing,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: switch (_phase) {
              _Phase.summary => _buildSummary(context),
              _Phase.gate => _buildGate(context),
              _Phase.processing => _buildProcessing(context),
              _Phase.done => _buildDone(context),
              _Phase.failed => _buildFailed(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('purchase-summary'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: item.icon),
        const SizedBox(height: 12),
        Text(
          item.title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          'Pago único · la compra es simulada',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        item.summary,
        const SizedBox(height: 8),
        FilledButton(
          key: const ValueKey('purchase-pay-button'),
          onPressed: sfxTap(_openGate),
          style: FilledButton.styleFrom(
            backgroundColor: item.accent,
            foregroundColor: item.onAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            'Pagar ${item.price}',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('purchase-cancel-button'),
          onPressed: sfxTap(() => Navigator.of(context).pop(false), sfx: Sfx.back),
          child: const Text('Ahora no'),
        ),
        // Para la demo: muestra cómo se ve un pago rechazado.
        Align(
          child: TextButton(
            key: const ValueKey('purchase-reject-toggle'),
            onPressed: () => setState(() => _rejectNext = !_rejectNext),
            child: Text(
              _rejectNext
                  ? 'Demo: el pago será rechazado (tocá para desactivar)'
                  : 'Demo: simular pago rechazado',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGate(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('purchase-gate'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Icon(Icons.family_restroom_rounded,
              size: 52, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 10),
        Text(
          'Pedile a una persona adulta',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          'Resolvé esta cuenta para seguir con la compra',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 14),
        Text(
          _question.text,
          key: const ValueKey('gate-question'),
          textAlign: TextAlign.center,
          style: theme.textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (_wrongAnswer)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Esa no es. Probá con esta otra cuenta.',
              key: const ValueKey('gate-wrong'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final option in _question.options)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: OutlinedButton(
                    key: ValueKey('gate-option-$option'),
                    onPressed: sfxTap(() => _answer(option)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      '$option',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('purchase-gate-cancel'),
          onPressed: sfxTap(() => Navigator.of(context).pop(false), sfx: Sfx.back),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _buildProcessing(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const ValueKey('purchase-processing'),
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 4),
          ),
          const SizedBox(height: 18),
          Text(
            'Procesando el pago…',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            'Es una simulación, no se cobra nada',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildDone(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('purchase-done'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: item.icon),
        const SizedBox(height: 12),
        Text(
          item.successTitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        if (item.successSubtitle != null)
          Text(
            item.successSubtitle!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        if (item.successBody != null) ...[
          const SizedBox(height: 18),
          item.successBody!,
        ],
        const SizedBox(height: 14),
        FilledButton(
          key: const ValueKey('purchase-done-button'),
          onPressed: sfxTap(() => Navigator.of(context).pop(true)),
          style: FilledButton.styleFrom(
            backgroundColor: item.accent,
            foregroundColor: item.onAccent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            item.doneLabel,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }

  Widget _buildFailed(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('purchase-failed'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Icon(Icons.error_outline_rounded,
              size: 56, color: theme.colorScheme.error),
        ),
        const SizedBox(height: 12),
        Text(
          'No pudimos procesar el pago',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          'No se cobró nada. Podés intentarlo de nuevo.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('purchase-retry-button'),
          onPressed: sfxTap(_pay),
          child: const Text('Reintentar'),
        ),
        const SizedBox(height: 6),
        TextButton(
          key: const ValueKey('purchase-close-button'),
          onPressed: sfxTap(() => Navigator.of(context).pop(false), sfx: Sfx.back),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
