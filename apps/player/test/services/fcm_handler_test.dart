import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/data/providers.dart';
import 'package:player/data/remote/sync_api_client.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/providers.dart';
import 'package:player/services/fcm_handler.dart';
import 'package:player/services/secure_storage.dart';

class _MockSyncApi extends Mock implements SyncApiClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('registerToken', () {
    test('sends the token through SyncApiClient (device JWT), not anon',
        () async {
      final api = _MockSyncApi();
      when(() => api.registerFcmToken(any(), any())).thenAnswer((_) async {});
      final container = ProviderContainer(
        overrides: [
          credentialsProvider.overrideWith(
            (ref) async =>
                const DeviceCredentials(deviceId: 'device-1', jwt: 'jwt-1'),
          ),
          syncApiClientProvider.overrideWith((ref, creds) => api),
        ],
      );
      addTearDown(container.dispose);

      final handler = FcmHandlerImpl(ref: container);
      await handler.registerToken('tok-123');

      verify(() => api.registerFcmToken('device-1', 'tok-123')).called(1);
    });

    test('is a no-op when the device is not paired yet', () async {
      final api = _MockSyncApi();
      final container = ProviderContainer(
        overrides: [
          credentialsProvider.overrideWith((ref) async => null),
          syncApiClientProvider.overrideWith((ref, creds) => api),
        ],
      );
      addTearDown(container.dispose);

      final handler = FcmHandlerImpl(ref: container);
      await handler.registerToken('tok-123');

      verifyNever(() => api.registerFcmToken(any(), any()));
    });

    test('swallows network errors (best effort)', () async {
      final api = _MockSyncApi();
      when(() => api.registerFcmToken(any(), any()))
          .thenThrow(Exception('network down'));
      final container = ProviderContainer(
        overrides: [
          credentialsProvider.overrideWith(
            (ref) async =>
                const DeviceCredentials(deviceId: 'device-1', jwt: 'jwt-1'),
          ),
          syncApiClientProvider.overrideWith((ref, creds) => api),
        ],
      );
      addTearDown(container.dispose);

      final handler = FcmHandlerImpl(ref: container);
      await expectLater(handler.registerToken('tok-123'), completes);
    });
  });

  test('onMessage with type=playlist_published bumps forceSyncRequestProvider',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final before = container.read(forceSyncRequestProvider);
    handler.onMessage({'type': 'playlist_published'});
    final after = container.read(forceSyncRequestProvider);
    expect(after, before + 1);
  });

  test('onMessage with type=assignment_changed bumps forceSyncRequestProvider',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final before = container.read(forceSyncRequestProvider);
    handler.onMessage({'type': 'assignment_changed', 'playlist_id': ''});
    expect(container.read(forceSyncRequestProvider), before + 1);
  });

  test('onMessage with type=revoked bumps fcmRevokedSignalProvider', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final before = container.read(fcmRevokedSignalProvider);
    handler.onMessage({'type': 'revoked'});
    expect(container.read(fcmRevokedSignalProvider), before + 1);
  });

  test('onMessage with unknown type is a no-op', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = FcmHandlerImpl(ref: container);
    final beforeSync = container.read(forceSyncRequestProvider);
    final beforeRevoke = container.read(fcmRevokedSignalProvider);
    handler.onMessage({'type': 'unknown_type'});
    expect(container.read(forceSyncRequestProvider), beforeSync);
    expect(container.read(fcmRevokedSignalProvider), beforeRevoke);
  });
}
