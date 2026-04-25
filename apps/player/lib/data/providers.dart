import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:player/data/local/app_database.dart';
import 'package:player/data/local/cache_storage.dart';
import 'package:player/data/remote/sync_api_client.dart';
import 'package:player/data/sync_service.dart';
import 'package:player/providers.dart';
import 'package:player/services/secure_storage.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final cacheStorageProvider = Provider<CacheStorage>((ref) {
  return CacheStorage(ref.watch(appDatabaseProvider));
});

final syncApiClientProvider =
    Provider.family<SyncApiClient, DeviceCredentials>((ref, creds) {
  return SyncApiClient(
    baseUrl: supabaseUrl,
    anonKey: supabaseAnonKey,
    deviceJwt: creds.jwt,
  );
});

final syncServiceProvider =
    Provider.family<SyncService, DeviceCredentials>((ref, creds) {
  return SyncService(
    api: ref.watch(syncApiClientProvider(creds)),
    db: ref.watch(appDatabaseProvider),
    storage: ref.watch(cacheStorageProvider),
    deviceId: creds.deviceId,
  );
});

/// Watches all items of a playlist, ordered by position.
final cachedPlaylistItemsProvider =
    StreamProvider.family<List<CachedPlaylistItem>, String>(
  (ref, playlistId) {
    final db = ref.watch(appDatabaseProvider);
    return (db.select(db.cachedPlaylistItems)
          ..where((t) => t.playlistId.equals(playlistId))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .watch();
  },
);

/// Currently assigned playlist row in the local cache. Stream so UI reacts to sync.
final cachedPlaylistProvider =
    FutureProvider<CachedPlaylistData?>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  // We don't have a direct device_playlists table locally; the SyncService fetches
  // the assignment server-side and writes the playlist into cachedPlaylist.
  // For Phase 5 we assume there is at most one playlist row in the local DB.
  final all = await db.select(db.cachedPlaylist).get();
  if (all.isEmpty) return null;
  return all.first;
});
