import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class FcmHandler {
  Future<void> registerToken(String token);
  void onMessage(Map<String, String> data);
}

class FcmHandlerImpl implements FcmHandler {
  FcmHandlerImpl({required this.ref, SupabaseClient? client}) : _client = client;

  final ProviderContainer ref;
  final SupabaseClient? _client;

  static const _channel = MethodChannel('app.player/fcm');

  /// Wires the MethodChannel handler. Call once at app startup.
  void wireChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onTokenRefresh':
          final token = call.arguments as String?;
          if (token != null) await registerToken(token);
          break;
        case 'onMessage':
          final raw = call.arguments;
          if (raw is Map) {
            onMessage(raw.map((k, v) => MapEntry(k.toString(), v.toString())));
          }
          break;
      }
      return null;
    });
  }

  @override
  Future<void> registerToken(String token) async {
    final creds = await ref.read(credentialsProvider.future);
    if (creds == null) {
      // Will be retried on next pairing complete (PairingScreen calls registerToken too).
      return;
    }
    final client = _client ?? Supabase.instance.client;
    try {
      await client.from('devices').update({'fcm_token': token}).eq('id', creds.deviceId);
    } catch (_) {
      // Best-effort. Next refresh will retry. Polling 15min keeps things working anyway.
    }
  }

  @override
  void onMessage(Map<String, String> data) {
    switch (data['type']) {
      case 'playlist_published':
      case 'assignment_changed':
        ref.read(forceSyncRequestProvider.notifier).state++;
        break;
      case 'revoked':
        ref.read(fcmRevokedSignalProvider.notifier).state++;
        break;
      default:
        break;
    }
  }
}

final fcmHandlerProvider = Provider<FcmHandler>((ref) {
  throw UnimplementedError(
    'fcmHandlerProvider must be overridden at app startup with a real container',
  );
});
