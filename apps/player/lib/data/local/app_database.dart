import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class CachedPlaylist extends Table {
  TextColumn get id => text()();
  TextColumn get establishmentId => text().named('establishment_id')();
  TextColumn get name => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  BoolColumn get audioEnabled =>
      boolean().named('audio_enabled').withDefault(const Constant(false))();
  DateTimeColumn get publishedAt => dateTime().nullable().named('published_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class CachedPlaylistItems extends Table {
  TextColumn get id => text()();
  TextColumn get playlistId => text().named('playlist_id')();
  TextColumn get mediaId => text().named('media_id')();
  IntColumn get position => integer()();
  IntColumn get displayDurationSec =>
      integer().named('display_duration_sec').withDefault(const Constant(10))();
  DateTimeColumn get startsAt => dateTime().nullable().named('starts_at')();
  DateTimeColumn get endsAt => dateTime().nullable().named('ends_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class PendingPlaybackLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get mediaId => text().named('media_id')();
  IntColumn get durationSec => integer().named('duration_sec')();
  IntColumn get capturedAt =>
      integer().named('captured_at')(); // unix ms
}

class CachedMedia extends Table {
  TextColumn get id => text()();
  TextColumn get establishmentId => text().named('establishment_id')();
  TextColumn get type => text()(); // 'video' | 'image'
  TextColumn get filePath => text().named('file_path')();
  TextColumn get localPath => text().nullable().named('local_path')();
  IntColumn get fileSize => integer().named('file_size')();
  TextColumn get mimeType => text().named('mime_type')();
  TextColumn get checksumSha256 => text().named('checksum_sha256')();
  TextColumn get originalFilename => text().named('original_filename')();
  IntColumn get downloadedAt =>
      integer().nullable().named('downloaded_at')(); // unix ms
  IntColumn get lastUsedAt =>
      integer().nullable().named('last_used_at')(); // unix ms (LRU)

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    CachedPlaylist,
    CachedPlaylistItems,
    CachedMedia,
    PendingPlaybackLogs,
    LocalSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pendingPlaybackLogs);
          }
          if (from < 3) {
            await m.createTable(localSettings);
          }
        },
      );

  // ----- Queries -----

  Future<CachedPlaylistData?> getPlaylist(String id) =>
      (select(cachedPlaylist)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<CachedPlaylistItem>> itemsFor(String playlistId) =>
      (select(cachedPlaylistItems)
            ..where((t) => t.playlistId.equals(playlistId))
            ..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .get();

  Stream<List<CachedPlaylistItem>> watchItemsFor(String playlistId) =>
      (select(cachedPlaylistItems)
            ..where((t) => t.playlistId.equals(playlistId))
            ..orderBy([(t) => OrderingTerm(expression: t.position)]))
          .watch();

  Future<CachedMediaData?> getMedia(String id) =>
      (select(cachedMedia)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<CachedMediaData>> getAllMedia() => select(cachedMedia).get();

  Future<int> totalCacheSize() async {
    final all = await getAllMedia();
    return all
        .where((m) => m.localPath != null)
        .fold<int>(0, (sum, m) => sum + m.fileSize);
  }

  // ----- Mutations -----

  Future<void> upsertPlaylist(CachedPlaylistCompanion data) =>
      into(cachedPlaylist).insertOnConflictUpdate(data);

  Future<void> replaceItems(
    String playlistId,
    List<CachedPlaylistItemsCompanion> items,
  ) async {
    await transaction(() async {
      await (delete(cachedPlaylistItems)
            ..where((t) => t.playlistId.equals(playlistId)))
          .go();
      if (items.isNotEmpty) {
        await batch((b) => b.insertAll(cachedPlaylistItems, items));
      }
    });
  }

  /// Removes every cached playlist (and its items) except [keepId]. A device
  /// has a single assignment; stale rows made the playlist lookup pick an
  /// arbitrary playlist after a reassignment.
  Future<void> purgePlaylistsExcept(String keepId) async {
    await transaction(() async {
      await (delete(cachedPlaylistItems)
            ..where((t) => t.playlistId.isNotValue(keepId)))
          .go();
      await (delete(cachedPlaylist)..where((t) => t.id.isNotValue(keepId)))
          .go();
    });
  }

  /// Clears every cached playlist and item (device unassigned → standby).
  Future<void> clearPlaylists() async {
    await transaction(() async {
      await delete(cachedPlaylistItems).go();
      await delete(cachedPlaylist).go();
    });
  }

  Future<void> upsertMedia(CachedMediaCompanion data) =>
      into(cachedMedia).insertOnConflictUpdate(data);

  Future<void> markMediaDownloaded(String id, String localPath) =>
      (update(cachedMedia)..where((t) => t.id.equals(id))).write(
        CachedMediaCompanion(
          localPath: Value(localPath),
          downloadedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> touchMedia(String id) =>
      (update(cachedMedia)..where((t) => t.id.equals(id))).write(
        CachedMediaCompanion(
          lastUsedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );

  Future<void> deleteMedia(String id) =>
      (delete(cachedMedia)..where((t) => t.id.equals(id))).go();

  // ----- Pending playback logs (offline queue) -----

  Future<int> enqueuePlaybackLog({
    required String mediaId,
    required int durationSec,
  }) {
    return into(pendingPlaybackLogs).insert(
      PendingPlaybackLogsCompanion(
        mediaId: Value(mediaId),
        durationSec: Value(durationSec),
        capturedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<List<PendingPlaybackLog>> pendingPlaybackLogsAll() {
    return (select(pendingPlaybackLogs)
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
  }

  Future<void> deletePendingPlaybackLog(int id) =>
      (delete(pendingPlaybackLogs)..where((t) => t.id.equals(id))).go();

  // ----- Local settings (KV) -----

  Future<String?> getSetting(String key) async {
    final row = await (select(localSettings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> upsertSetting(String key, String value) =>
      into(localSettings).insertOnConflictUpdate(
        LocalSettingsCompanion(
          key: Value(key),
          value: Value(value),
        ),
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'player_cache.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
