import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class FcmHandler {
  Future<void> registerToken(String token);
  Future<void> registerCurrentToken();
  void onMessage(Map<String, String> data);
}

class FcmHandlerImpl implements FcmHandler {
  FcmHandlerImpl({required this.ref, SupabaseClient? client}) : _client = client;

  final ProviderContainer ref;
  final SupabaseClient? _client;

  static const _eventsChannel = MethodChannel('app.player/fcm_events');
  static const _commandsChannel = MethodChannel('app.player/fcm');

  /// Wires the MethodChannel handler. Call once at app startup.
  void wireChannel() {
    _eventsChannel.setMethodCallHandler((call) async {
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
  Future<void> registerCurrentToken() async {
    try {
      final token = await _commandsChannel.invokeMethod<String>('getCurrentToken');
      if (token != null) {
        await registerToken(token);
      }
    } catch (_) {
      // Best-effort. Polling 15 min covers if this fails.
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

FcmHandler? _globalFcmHandler;

void setGlobalFcmHandler(FcmHandler handler) {
  _globalFcmHandler = handler;
}

final fcmHandlerProvider = Provider<FcmHandler>((ref) {
  final handler = _globalFcmHandler;
  if (handler == null) {
    throw StateError('fcmHandlerProvider read before setGlobalFcmHandler() was called');
  }
  return handler;
});
