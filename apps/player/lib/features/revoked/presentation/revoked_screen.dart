import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/providers.dart';

class RevokedScreen extends ConsumerWidget {
  const RevokedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.red.shade900,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.block, size: 96, color: Colors.white),
            const SizedBox(height: 24),
            const Text(
              'APPAREIL RÉVOQUÉ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Cet appareil a été désactivé par l'administrateur.",
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 48),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: () async {
                await ref.read(secureStorageProvider).clear();
                ref.invalidate(credentialsProvider);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Ré-appairer cet appareil'),
            ),
          ],
        ),
      ),
    );
  }
}
