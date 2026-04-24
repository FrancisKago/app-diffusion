import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/app.dart';
import 'package:player/services/secure_storage.dart';

class ReadyScreen extends ConsumerWidget {
  const ReadyScreen({required this.creds, super.key});

  final DeviceCredentials creds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Center(
            child: Text(
              'APPAREIL ACTIF',
              style: TextStyle(
                color: Colors.white,
                fontSize: 48,
                letterSpacing: 6,
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Row(
              children: [
                Text(
                  'Device: ${creds.deviceId.substring(0, 8)}…',
                  style: const TextStyle(color: Colors.white30, fontSize: 12),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white30),
                  tooltip: 'Déconnecter (dev)',
                  onPressed: () async {
                    await ref.read(secureStorageProvider).clear();
                    ref.invalidate(credentialsProvider);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
