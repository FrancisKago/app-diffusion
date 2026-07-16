import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:player/data/providers.dart';
import 'package:player/features/lifecycle/application/cache_readiness.dart';
import 'package:player/features/lifecycle/application/foreground_service_controller.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';
import 'package:player/providers.dart';
import 'package:shared/shared.dart';

final batteryOptimCheckerProvider = Provider<BatteryOptimChecker>((ref) {
  return NativeBatteryOptimChecker();
});

final foregroundServiceProvider = Provider<ForegroundServiceController>((ref) {
  return ForegroundServiceController();
});

final isBatteryOptimExcludedProvider = FutureProvider<bool>((ref) async {
  return ref.watch(batteryOptimCheckerProvider).isExcluded();
});

final foregroundServiceRunningProvider = FutureProvider<bool>((ref) async {
  return ref.watch(foregroundServiceProvider).isRunning();
});

final lastSyncOkProvider = StateProvider<DateTime?>((ref) => null);

/// Last sync error message (null when the last sync succeeded). Set by
/// PlayerScreen so the hidden admin screen can surface why sync is failing.
final lastSyncErrorProvider = StateProvider<String?>((ref) => null);

/// Local-cache readiness + active-playlist snapshot for the admin screen.
/// Recomputed each time it is read (invalidate to refresh).
class PlayerDiagnostics {
  const PlayerDiagnostics({
    required this.playlistName,
    required this.playlistVersion,
    required this.itemCount,
    required this.readiness,
    required this.cacheBytes,
  });

  final String? playlistName;
  final int playlistVersion;
  final int itemCount;
  final CacheReadiness readiness;
  final int cacheBytes;
}

final playerDiagnosticsProvider =
    FutureProvider<PlayerDiagnostics>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final playlists = await db.select(db.cachedPlaylist).get();
  final playlist = playlists.isEmpty ? null : playlists.first;
  final cacheBytes = await db.totalCacheSize();

  if (playlist == null) {
    return PlayerDiagnostics(
      playlistName: null,
      playlistVersion: 0,
      itemCount: 0,
      readiness: computeCacheReadiness(const [], (_) => false),
      cacheBytes: cacheBytes,
    );
  }

  final items = await db.itemsFor(playlist.id);
  // Distinct media referenced by the playlist, in first-seen order.
  final seen = <String>{};
  final refs = <MediaRef>[];
  for (final item in items) {
    if (!seen.add(item.mediaId)) continue;
    final media = await db.getMedia(item.mediaId);
    refs.add(
      MediaRef(
        filename: media?.originalFilename ?? item.mediaId,
        localPath: media?.localPath,
      ),
    );
  }
  final readiness =
      computeCacheReadiness(refs, (path) => File(path).existsSync());

  return PlayerDiagnostics(
    playlistName: playlist.name,
    playlistVersion: playlist.version,
    itemCount: items.length,
    readiness: readiness,
    cacheBytes: cacheBytes,
  );
});

final adminDiagnosticProvider = FutureProvider<AdminDiagnostic>((ref) async {
  final creds = await ref.watch(credentialsProvider.future);
  final pkg = await PackageInfo.fromPlatform();
  final batteryExcluded =
      await ref.watch(isBatteryOptimExcludedProvider.future);
  final serviceRunning =
      await ref.watch(foregroundServiceRunningProvider.future);
  final lastSync = ref.watch(lastSyncOkProvider);
  return AdminDiagnostic(
    appVersion: '${pkg.version}+${pkg.buildNumber}',
    deviceId: creds?.deviceId ?? '—',
    lastSyncOk: lastSync,
    foregroundServiceRunning: serviceRunning,
    batteryOptimExcluded: batteryExcluded,
  );
});

const _kFirstRunBatteryShownKey = 'first_run_battery_shown';

final firstRunBatteryShownProvider = FutureProvider<bool>((ref) async {
  final db = ref.read(appDatabaseProvider);
  final v = await db.getSetting(_kFirstRunBatteryShownKey);
  return v == '1';
});

final markFirstRunBatteryShownProvider =
    Provider<Future<void> Function()>((ref) {
  return () async {
    final db = ref.read(appDatabaseProvider);
    await db.upsertSetting(_kFirstRunBatteryShownKey, '1');
    ref.invalidate(firstRunBatteryShownProvider);
  };
});

/// Increment to request an out-of-band sync from the PlayerScreen.
final forceSyncRequestProvider = StateProvider<int>((ref) => 0);

/// Bumped (incrementing counter) by FcmHandler when the device receives a
/// `revoked` push from the backend. PlayerScreen listens and switches to
/// RevokedScreen immediately.
final fcmRevokedSignalProvider = StateProvider<int>((ref) => 0);
