import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/features/pairing/presentation/pairing_screen.dart';
import 'package:player/features/player/presentation/player_screen.dart';
import 'package:player/providers.dart';

class PlayerApp extends ConsumerWidget {
  const PlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creds = ref.watch(credentialsProvider);
    return MaterialApp(
      title: 'App Diffusion — Player',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: creds.when(
        loading: () => const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Text('Erreur: $e',
                style: const TextStyle(color: Colors.white)),
          ),
        ),
        data: (c) => c == null
            ? const PairingScreen()
            : WithForegroundTask(child: PlayerScreen(creds: c)),
      ),
    );
  }
}
