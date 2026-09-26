import 'package:flutter/material.dart';
import '../state/game_state.dart';

/// Monetizacion simulada: comprar diamantes no llama a ningun backend real,
/// solo suma al contador local (cumple "simular monetizacion").
void showDiamondShopModal(BuildContext context, GameState gameState) {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      final packs = [100, 500, 1200];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Comprar diamantes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              for (final pack in packs)
                ListTile(
                  leading: const Icon(Icons.diamond),
                  title: Text('x$pack diamantes'),
                  trailing: FilledButton(
                    onPressed: () {
                      gameState.addDiamonds(pack);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Comprar'),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}
