import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/features/pairing/presentation/pairing_screen.dart';
import 'package:player/features/ready/presentation/ready_screen.dart';
import 'package:player/services/pairing_service.dart';
import 'package:player/services/secure_storage.dart';

const _kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://10.0.2.2:54321',
);
const _kAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final pairingServiceProvider = Provider<PairingService>((ref) {
  return PairingService(baseUrl: _kSupabaseUrl, anonKey: _kAnonKey);
});

final credentialsProvider = FutureProvider<DeviceCredentials?>((ref) {
  return ref.watch(secureStorageProvider).readCredentials();
});

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
            child: Text(
              'Erreur: $e',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        data: (c) => c == null ? const PairingScreen() : ReadyScreen(creds: c),
      ),
    );
  }
}
