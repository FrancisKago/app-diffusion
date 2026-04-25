import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/services/pairing_service.dart';
import 'package:player/services/secure_storage.dart';

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://10.0.2.2:54321',
);

const supabaseAnonKey =
    String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final pairingServiceProvider = Provider<PairingService>((ref) {
  return PairingService(baseUrl: supabaseUrl, anonKey: supabaseAnonKey);
});

final credentialsProvider = FutureProvider<DeviceCredentials?>((ref) {
  return ref.watch(secureStorageProvider).readCredentials();
});
