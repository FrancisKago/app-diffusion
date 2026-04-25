import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/application/lifecycle_providers.dart';
import 'package:player/services/fcm_handler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
