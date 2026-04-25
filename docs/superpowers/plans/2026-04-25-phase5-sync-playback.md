# Phase 5 — Sync Android + Lecteur — Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development to implement task-by-task.

**Goal:** Le Player Android, une fois appairé, télécharge la playlist assignée à son device, joue en boucle plein écran, filtre par dates de campagne, continue à fonctionner hors-ligne, et rattrape les modifications dès retour réseau. La publication d'une playlist depuis le back office incrémente sa `version` ; le player détecte le changement via polling (15 min) ou au retour de connexion.

**Architecture:**
- **Sync polling-first** : pas de FCM en Phase 5 (différé en Phase 5.5). Le player polle la playlist toutes les 15 min via REST Supabase avec son JWT device. La latence max de réception est donc 15 min — acceptable pour un MVP signage.
- **Cache local SQLite** via `drift` : tables `cached_playlist`, `cached_playlist_items`, `cached_media` qui mirrorent l'état serveur.
- **Téléchargement médias** via `dio` avec resume + vérification SHA-256, vers `getApplicationSupportDirectory()/media/`.
- **Lecture en boucle** : `PlayerScreen` parcourt les items locaux filtrés par dates, gère vidéo (`video_player`) et image (durée paramétrable).
- **Connectivité** : `connectivity_plus` déclenche un sync au retour wifi/data.
- **Foreground service** : reporté à 5.5 (l'app étant en kiosque tablette, foreground naturel suffit pour la démo).

**Tech Stack player additions:**
- `drift` ^2.21+ + `drift_dev` + `sqlite3_flutter_libs`
- `dio` ^5.7+ pour les downloads avec resume
- `path_provider` pour le cache directory
- `connectivity_plus` ^6.1+ pour les transitions réseau
- `crypto` ^3.0+ pour vérification SHA-256
- `wakelock_plus` ^1.2+ pour empêcher l'écran de s'éteindre

---

## File Structure additions

```
apps/player/
├── lib/
│   ├── main.dart                                # modif : init wakelock
│   ├── app.dart                                 # modif : route to PlayerScreen au lieu de ReadyScreen
│   ├── data/
│   │   ├── local/
│   │   │   ├── app_database.dart                # drift schema + DAO
│   │   │   └── cache_storage.dart               # gestion fichiers + LRU
│   │   ├── remote/
│   │   │   └── sync_api_client.dart             # HTTP client authentifié device JWT
│   │   └── sync_service.dart                    # orchestre fetch + diff + download
│   ├── services/
│   │   ├── pairing_service.dart                 # existant
│   │   ├── secure_storage.dart                  # existant
│   │   └── playback_service.dart                # boucle + filtrage dates
│   └── features/
│       ├── pairing/                             # existant
│       └── player/
│           └── presentation/
│               ├── player_screen.dart           # remplace ready_screen
│               └── standby_screen.dart          # quand pas d'items à jouer
└── test/
    ├── data/
    │   └── sync_service_test.dart               # diff playlist
    └── services/
        └── playback_service_test.dart           # filtrage dates
```

---

## Task 1 — Player deps + Android permissions

**Files:**
- Modify: `apps/player/pubspec.yaml`
- Modify: `apps/player/android/app/src/main/AndroidManifest.xml`

Ajouter dépendances :
```yaml
dependencies:
  flutter:
    sdk: flutter
  shared:
    path: ../../packages/shared
  connectivity_plus: ^6.1.0
  crypto: ^3.0.5
  dio: ^5.7.0
  drift: ^2.21.0
  flutter_riverpod: ^2.6.1
  flutter_secure_storage: ^9.2.2
  http: ^1.2.2
  path: ^1.9.0
  path_provider: ^2.1.5
  sqlite3_flutter_libs: ^0.5.27
  uuid: ^4.5.1
  video_player: ^2.9.2
  wakelock_plus: ^1.2.10

dev_dependencies:
  flutter_test:
    sdk: flutter
  build_runner: ^2.4.13
  drift_dev: ^2.21.0
  very_good_analysis: ^6.0.0
  mocktail: ^1.0.4
```

Permissions Android (déjà `INTERNET` ; on ajoute `ACCESS_NETWORK_STATE` pour `connectivity_plus` et `WAKE_LOCK` pour wakelock_plus) :
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
```

Run `flutter pub get` from repo root. Verify analyze.
Commit: `feat(player): add deps for sync and playback (drift, dio, connectivity)`

---

## Task 2 — Drift schema + DAO

**Files:**
- Create: `apps/player/lib/data/local/app_database.dart`

Schema avec 3 tables qui mirrorent le serveur :

```dart
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart' show driftDatabase;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class CachedPlaylist extends Table {
  TextColumn get id => text()();
  TextColumn get establishmentId => text().named('establishment_id')();
  TextColumn get name => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  BoolColumn get audioEnabled => boolean().named('audio_enabled').withDefault(const Constant(false))();
  DateTimeColumn get publishedAt => dateTime().nullable().named('published_at')();
  @override Set<Column> get primaryKey => {id};
}

class CachedPlaylistItems extends Table {
  TextColumn get id => text()();
  TextColumn get playlistId => text().named('playlist_id')();
  TextColumn get mediaId => text().named('media_id')();
  IntColumn get position => integer()();
  IntColumn get displayDurationSec => integer().named('display_duration_sec').withDefault(const Constant(10))();
  DateTimeColumn get startsAt => dateTime().nullable().named('starts_at')();
  DateTimeColumn get endsAt => dateTime().nullable().named('ends_at')();
  @override Set<Column> get primaryKey => {id};
}

class CachedMedia extends Table {
  TextColumn get id => text()();
  TextColumn get establishmentId => text().named('establishment_id')();
  TextColumn get type => text()();        // 'video' | 'image'
  TextColumn get filePath => text().named('file_path')();   // path serveur
  TextColumn get localPath => text().named('local_path').nullable()(); // chemin local après download
  IntColumn get fileSize => integer().named('file_size')();
  TextColumn get mimeType => text().named('mime_type')();
  TextColumn get checksumSha256 => text().named('checksum_sha256')();
  TextColumn get originalFilename => text().named('original_filename')();
  IntColumn get downloadedAt => integer().nullable().named('downloaded_at')(); // unix ms
  IntColumn get lastUsedAt => integer().nullable().named('last_used_at')();    // pour LRU
  @override Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [CachedPlaylist, CachedPlaylistItems, CachedMedia])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override int get schemaVersion => 1;

  // Queries
  Future<CachedPlaylistData?> getPlaylist(String id) =>
      (select(cachedPlaylist)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<CachedPlaylistItemsData>> itemsFor(String playlistId) =>
      (select(cachedPlaylistItems)
        ..where((t) => t.playlistId.equals(playlistId))
        ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .get();

  Future<CachedMediaData?> getMedia(String id) =>
      (select(cachedMedia)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<CachedMediaData>> getAllMedia() => select(cachedMedia).get();

  Future<int> totalCacheSize() async {
    final all = await getAllMedia();
    return all.where((m) => m.localPath != null).fold(0, (sum, m) => sum + m.fileSize);
  }

  Future<void> upsertPlaylist(CachedPlaylistCompanion data) =>
      into(cachedPlaylist).insertOnConflictUpdate(data);

  Future<void> replaceItems(String playlistId, List<CachedPlaylistItemsCompanion> items) async {
    await transaction(() async {
      await (delete(cachedPlaylistItems)..where((t) => t.playlistId.equals(playlistId))).go();
      await batch((b) => b.insertAll(cachedPlaylistItems, items));
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
        CachedMediaCompanion(lastUsedAt: Value(DateTime.now().millisecondsSinceEpoch)),
      );

  Future<void> deleteMedia(String id) =>
      (delete(cachedMedia)..where((t) => t.id.equals(id))).go();
}

QueryExecutor _openConnection() {
  return driftDatabase(
    name: 'player_cache',
    native: const DriftNativeOptions(),
  );
}
```

Note : `drift_flutter` n'est pas dans nos deps — utiliser `LazyDatabase` et `getApplicationSupportDirectory` à la place. Voir doc drift pour le boilerplate `_openConnection`.

Run `dart run build_runner build --delete-conflicting-outputs` from `apps/player/`. Verify analyze.

Commit: `feat(player): add drift schema for local cache (playlist, items, media)`

---

## Task 3 — Cache storage helper

**Files:**
- Create: `apps/player/lib/data/local/cache_storage.dart`

Gère le répertoire de cache + purge LRU :

```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

class CacheStorage {
  CacheStorage(this._db);
  final AppDatabase _db;

  static const int maxCacheBytes = 2 * 1024 * 1024 * 1024; // 2 GB

  Future<Directory> _mediaDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'media'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> resolveLocalFile(String mediaId, String extension) async {
    final dir = await _mediaDir();
    return File(p.join(dir.path, '$mediaId.$extension'));
  }

  Future<int> currentSize() async {
    final all = await _db.getAllMedia();
    return all.where((m) => m.localPath != null).fold(0, (s, m) => s + m.fileSize);
  }

  /// Purges least-recently-used cached media until total size <= [maxCacheBytes].
  /// Skips media currently referenced in the active playlist (passed in [keepIds]).
  Future<int> purgeLruIfNeeded(Set<String> keepIds) async {
    var size = await currentSize();
    if (size <= maxCacheBytes) return 0;

    final all = await _db.getAllMedia();
    final purgeable = all
        .where((m) => m.localPath != null && !keepIds.contains(m.id))
        .toList()
      ..sort((a, b) => (a.lastUsedAt ?? 0).compareTo(b.lastUsedAt ?? 0));

    var purged = 0;
    for (final m in purgeable) {
      if (size <= maxCacheBytes) break;
      try {
        final f = File(m.localPath!);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {/* best effort */}
      await _db.deleteMedia(m.id);
      size -= m.fileSize;
      purged++;
    }
    return purged;
  }
}
```

Commit: `feat(player): add cache storage with LRU purge`

---

## Task 4 — Authenticated REST client

**Files:**
- Create: `apps/player/lib/data/remote/sync_api_client.dart`

Client HTTP minimaliste pour parler à Supabase REST avec le JWT du device :

```dart
import 'dart:convert';
import 'package:dio/dio.dart';

class SyncApiClient {
  SyncApiClient({
    required this.baseUrl,
    required this.anonKey,
    required this.deviceJwt,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final String baseUrl;
  final String anonKey;
  final String deviceJwt;
  final Dio _dio;

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $deviceJwt',
        'Accept': 'application/json',
      };

  Future<Map<String, dynamic>?> getMyDevicePlaylistAssignment(String deviceId) async {
    final r = await _dio.get(
      '$baseUrl/rest/v1/device_playlists',
      queryParameters: {'device_id': 'eq.$deviceId', 'select': 'playlist_id'},
      options: Options(headers: _headers),
    );
    final data = r.data as List;
    if (data.isEmpty) return null;
    return Map<String, dynamic>.from(data.first as Map);
  }

  Future<Map<String, dynamic>> fetchPlaylist(String playlistId) async {
    final r = await _dio.get(
      '$baseUrl/rest/v1/playlists',
      queryParameters: {'id': 'eq.$playlistId', 'select': '*'},
      options: Options(headers: _headers),
    );
    final list = r.data as List;
    if (list.isEmpty) throw StateError('Playlist not found');
    return Map<String, dynamic>.from(list.first as Map);
  }

  Future<List<Map<String, dynamic>>> fetchPlaylistItems(String playlistId) async {
    final r = await _dio.get(
      '$baseUrl/rest/v1/playlist_items',
      queryParameters: {
        'playlist_id': 'eq.$playlistId',
        'select': '*',
        'order': 'position.asc',
      },
      options: Options(headers: _headers),
    );
    return (r.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchMedia(List<String> ids) async {
    if (ids.isEmpty) return [];
    final inFilter = '(${ids.join(",")})';
    final r = await _dio.get(
      '$baseUrl/rest/v1/media',
      queryParameters: {'id': 'in.$inFilter', 'select': '*'},
      options: Options(headers: _headers),
    );
    return (r.data as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<String> signedUrlForMedia(String filePath, {int expiresInSeconds = 3600}) async {
    final r = await _dio.post(
      '$baseUrl/storage/v1/object/sign/media/$filePath',
      data: jsonEncode({'expiresIn': expiresInSeconds}),
      options: Options(headers: {..._headers, 'Content-Type': 'application/json'}),
    );
    final body = r.data as Map<String, dynamic>;
    final signedPath = body['signedURL'] ?? body['signedUrl'];
    if (signedPath == null) throw StateError('No signedURL in response: $body');
    // The response sometimes is a relative path like /object/sign/media/...
    if ((signedPath as String).startsWith('http')) return signedPath;
    return '$baseUrl/storage/v1$signedPath';
  }

  Future<void> heartbeat(String deviceId, {int? syncProgress, String? currentMediaId}) async {
    final patch = <String, dynamic>{
      'last_seen_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (syncProgress != null) patch['sync_progress'] = syncProgress;
    if (currentMediaId != null) patch['current_media_id'] = currentMediaId;
    await _dio.patch(
      '$baseUrl/rest/v1/devices',
      queryParameters: {'id': 'eq.$deviceId'},
      data: jsonEncode(patch),
      options: Options(headers: {..._headers, 'Content-Type': 'application/json'}),
    );
  }
}
```

Note: ajout de `current_media_id` et `sync_progress` columns sur `devices` à vérifier — si absentes, ajouter une migration légère. (Le spec section 4.1 les mentionne déjà donc on suppose présentes ; sinon mini-migration en Task 4.5.)

**Vérification** : lire `supabase/migrations/20260425100000_devices.sql` et confirmer que `current_media_id` et `sync_progress` existent. Si non → créer migration `20260426100000_devices_sync_columns.sql` qui les ajoute :
```sql
alter table public.devices
    add column if not exists current_media_id uuid references public.media(id) on delete set null,
    add column if not exists sync_progress int default 0;
```

Commit: `feat(player): add SyncApiClient for Supabase REST + Storage signed URLs`

---

## Task 5 — SyncService (diff + download orchestration)

**Files:**
- Create: `apps/player/lib/data/sync_service.dart`

Logique métier qui orchestre fetch playlist + items + media, diff contre cache local, télécharge les nouveaux médias, purge LRU.

```dart
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;

import 'local/app_database.dart';
import 'local/cache_storage.dart';
import 'remote/sync_api_client.dart';

class SyncResult {
  const SyncResult({
    required this.playlistVersion,
    required this.itemCount,
    required this.downloadedCount,
    required this.purgedCount,
  });
  final int playlistVersion;
  final int itemCount;
  final int downloadedCount;
  final int purgedCount;
}

class SyncService {
  SyncService({
    required this.api,
    required this.db,
    required this.storage,
    required this.deviceId,
  });

  final SyncApiClient api;
  final AppDatabase db;
  final CacheStorage storage;
  final String deviceId;

  Future<SyncResult?> sync() async {
    // 1. Find current playlist assignment
    final assignment = await api.getMyDevicePlaylistAssignment(deviceId);
    if (assignment == null) return null;
    final playlistId = assignment['playlist_id'] as String;

    // 2. Fetch playlist + items + media metadata
    final playlistJson = await api.fetchPlaylist(playlistId);
    final itemsJson = await api.fetchPlaylistItems(playlistId);
    final mediaIds = itemsJson.map((i) => i['media_id'] as String).toSet().toList();
    final mediaJson = await api.fetchMedia(mediaIds);

    // 3. Upsert into local cache
    await db.upsertPlaylist(CachedPlaylistCompanion(
      id: Value(playlistJson['id'] as String),
      establishmentId: Value(playlistJson['establishment_id'] as String),
      name: Value(playlistJson['name'] as String),
      version: Value(playlistJson['version'] as int? ?? 0),
      audioEnabled: Value((playlistJson['audio_enabled'] as bool?) ?? false),
      publishedAt: Value(playlistJson['published_at'] != null
          ? DateTime.parse(playlistJson['published_at'] as String)
          : null),
    ));

    final itemCompanions = itemsJson.map((i) => CachedPlaylistItemsCompanion(
          id: Value(i['id'] as String),
          playlistId: Value(i['playlist_id'] as String),
          mediaId: Value(i['media_id'] as String),
          position: Value(i['position'] as int),
          displayDurationSec: Value(i['display_duration_sec'] as int? ?? 10),
          startsAt: Value(i['starts_at'] != null
              ? DateTime.parse(i['starts_at'] as String)
              : null),
          endsAt: Value(i['ends_at'] != null
              ? DateTime.parse(i['ends_at'] as String)
              : null),
        )).toList();
    await db.replaceItems(playlistId, itemCompanions);

    for (final m in mediaJson) {
      await db.upsertMedia(CachedMediaCompanion(
        id: Value(m['id'] as String),
        establishmentId: Value(m['establishment_id'] as String),
        type: Value(m['type'] as String),
        filePath: Value(m['file_path'] as String),
        fileSize: Value(m['file_size'] as int),
        mimeType: Value(m['mime_type'] as String),
        checksumSha256: Value(m['checksum_sha256'] as String),
        originalFilename: Value(m['original_filename'] as String),
      ));
    }

    // 4. Download missing media
    var downloaded = 0;
    final total = mediaJson.length;
    for (var i = 0; i < total; i++) {
      final m = mediaJson[i];
      final mediaId = m['id'] as String;
      final cached = await db.getMedia(mediaId);
      if (cached?.localPath != null && File(cached!.localPath!).existsSync()) {
        continue;
      }
      try {
        final ext = _extensionFor(m['mime_type'] as String);
        final localFile = await storage.resolveLocalFile(mediaId, ext);
        final signedUrl = await api.signedUrlForMedia(m['file_path'] as String);

        // Use Dio download with progress (resume can be added later)
        await Dio().download(
          signedUrl,
          localFile.path,
          options: Options(headers: {'Accept': '*/*'}),
        );

        // Verify checksum
        final bytes = await localFile.readAsBytes();
        final actualChecksum = sha256.convert(bytes).toString();
        if (actualChecksum != (m['checksum_sha256'] as String)) {
          await localFile.delete();
          throw StateError('Checksum mismatch for media $mediaId');
        }

        await db.markMediaDownloaded(mediaId, localFile.path);
        downloaded++;
      } catch (e) {
        // Best-effort: skip failed download, will retry next sync
        // ignore: avoid_print
        print('Download failed for media $mediaId: $e');
      }

      // Heartbeat with progress
      final progress = ((i + 1) * 100 ~/ total).clamp(0, 100);
      try {
        await api.heartbeat(deviceId, syncProgress: progress);
      } catch (_) {/* best effort */}
    }

    // 5. LRU purge if cache too big
    final keepIds = mediaIds.toSet();
    final purged = await storage.purgeLruIfNeeded(keepIds);

    return SyncResult(
      playlistVersion: playlistJson['version'] as int? ?? 0,
      itemCount: itemsJson.length,
      downloadedCount: downloaded,
      purgedCount: purged,
    );
  }

  String _extensionFor(String mimeType) => switch (mimeType) {
        'video/mp4' => 'mp4',
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'bin',
      };
}
```

Commit: `feat(player): add SyncService orchestrating fetch/download/cache`

---

## Task 6 — PlaybackService (filtrage dates + boucle)

**Files:**
- Create: `apps/player/lib/services/playback_service.dart`
- Create: `apps/player/test/services/playback_service_test.dart`

Service pur (testable) qui filtre la liste d'items par dates et donne le prochain item à jouer.

Test (3 cas) :
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:player/data/local/app_database.dart';
import 'package:player/services/playback_service.dart';

void main() {
  CachedPlaylistItemsData _item(
    String id, {
    int position = 0,
    DateTime? startsAt,
    DateTime? endsAt,
  }) =>
      CachedPlaylistItemsData(
        id: id,
        playlistId: 'p1',
        mediaId: 'm1',
        position: position,
        displayDurationSec: 10,
        startsAt: startsAt,
        endsAt: endsAt,
      );

  group('PlaybackService.activeItems', () {
    test('keeps items with no date constraints', () {
      final now = DateTime.utc(2026, 5, 5);
      final items = [_item('a'), _item('b', position: 1)];
      expect(PlaybackService.activeItems(items, now), hasLength(2));
    });

    test('drops items before starts_at', () {
      final now = DateTime.utc(2026, 5, 5);
      final items = [
        _item('past', startsAt: DateTime.utc(2026, 5, 10)),
        _item('current', position: 1),
      ];
      final active = PlaybackService.activeItems(items, now);
      expect(active.map((i) => i.id), ['current']);
    });

    test('drops items after ends_at', () {
      final now = DateTime.utc(2026, 5, 5);
      final items = [
        _item('expired', endsAt: DateTime.utc(2026, 5, 1)),
        _item('current', position: 1),
      ];
      final active = PlaybackService.activeItems(items, now);
      expect(active.map((i) => i.id), ['current']);
    });
  });
}
```

Implementation:
```dart
import '../data/local/app_database.dart';

class PlaybackService {
  /// Returns items active at [now] : those without dates, OR within [starts_at, ends_at].
  static List<CachedPlaylistItemsData> activeItems(
    List<CachedPlaylistItemsData> items,
    DateTime now,
  ) {
    return items.where((i) {
      if (i.startsAt != null && now.isBefore(i.startsAt!)) return false;
      if (i.endsAt != null && now.isAfter(i.endsAt!)) return false;
      return true;
    }).toList();
  }
}
```

Run tests : `cd apps/player && flutter test test/services/playback_service_test.dart` → 3/3 pass.
Commit: `feat(player): add PlaybackService with date filtering and tests`

---

## Task 7 — Player providers (replace ready_screen)

**Files:**
- Create: `apps/player/lib/data/providers.dart`
- Modify: `apps/player/lib/app.dart` (route to PlayerScreen instead of ReadyScreen)

Providers Riverpod qui exposent : DB singleton, SyncApiClient (reconstruit quand JWT change), SyncService, current playlist + items.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart' show pairingServiceProvider; // for SUPABASE_URL/anon
import '../services/secure_storage.dart';
import 'local/app_database.dart';
import 'local/cache_storage.dart';
import 'remote/sync_api_client.dart';
import 'sync_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final cacheStorageProvider = Provider<CacheStorage>((ref) {
  return CacheStorage(ref.watch(appDatabaseProvider));
});

final syncApiClientProvider = Provider.family<SyncApiClient, DeviceCredentials>(
  (ref, creds) {
    // Constants from app.dart — re-imported via const for sandbox-safe values
    const url = String.fromEnvironment(
      'SUPABASE_URL',
      defaultValue: 'http://10.0.2.2:54321',
    );
    const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    return SyncApiClient(
      baseUrl: url,
      anonKey: anonKey,
      deviceJwt: creds.jwt,
    );
  },
);

final syncServiceProvider = Provider.family<SyncService, DeviceCredentials>(
  (ref, creds) {
    return SyncService(
      api: ref.watch(syncApiClientProvider(creds)),
      db: ref.watch(appDatabaseProvider),
      storage: ref.watch(cacheStorageProvider),
      deviceId: creds.deviceId,
    );
  },
);

final cachedPlaylistItemsProvider = StreamProvider.family<List<CachedPlaylistItemsData>, String>(
  (ref, playlistId) {
    final db = ref.watch(appDatabaseProvider);
    return (db.select(db.cachedPlaylistItems)
          ..where((t) => t.playlistId.equals(playlistId))
          ..orderBy([(t) => OrderingTerm(expression: t.position)]))
        .watch();
  },
);
```

Note : `OrderingTerm` import from `package:drift/drift.dart`. Adjust imports.

Modify `apps/player/lib/app.dart` — replace the `home: creds.when(... data: (c) => c == null ? PairingScreen() : ReadyScreen(creds: c))` with `... ReadyScreen(creds: c)` → `PlayerScreen(creds: c)`. Import the new screen.

Commit: `feat(player): wire sync providers and route to PlayerScreen`

---

## Task 8 — PlayerScreen (orchestrate sync loop + connectivity)

**Files:**
- Create: `apps/player/lib/features/player/presentation/player_screen.dart`
- Create: `apps/player/lib/features/player/presentation/standby_screen.dart`

Screen principal qui :
1. Au mount : lance un sync immédiat
2. Toutes les 15 min : re-sync (Timer.periodic)
3. Sur changement de connectivité (offline→online) : re-sync
4. Affiche le current item si playlist disponible, sinon StandbyScreen
5. Boucle sur les items : video → wait until done, image → wait `display_duration_sec` puis next

Squelette détaillé fourni dans le subagent prompt à l'exécution. Critères clés :
- Utilise `wakelockPlus.WakelockPlus.enable()` à l'init
- Gère proprement le `VideoPlayerController.dispose()` entre items
- Filtre via `PlaybackService.activeItems(items, DateTime.now())`
- Heartbeat toutes les 5 min avec `current_media_id`

Commit: `feat(player): add PlayerScreen with loop, sync, connectivity hook`

---

## Task 9 — Backoffice : status badge + sync progress sur liste devices

**Files:**
- Modify: `apps/player/lib/...` (none for this task)
- Modify: `apps/backoffice/lib/features/devices/presentation/devices_list_screen.dart`
- Modify: `apps/backoffice/lib/features/devices/data/devices_repository.dart` (si besoin pour récupérer last_seen_at + sync_progress)

Afficher pour chaque device :
- Pastille verte si `last_seen_at` < 10 min, grise sinon
- `sync_progress` (% si != 100)
- Bouton "Forcer sync" (bonus, optionnel — incrémente `playlist.version` pour déclencher la détection au prochain poll)

Read le model `Device` actuel — il faut probablement ajouter `lastSeenAt` et `syncProgress` au model freezed. Si le model n'a pas ces champs, étendre `Device` dans `packages/shared/lib/src/models/device.dart` puis regen.

Commit: `feat(backoffice): add device status badge with last_seen and sync progress`

---

## Task 10 — Phase 5 demo doc + README

**Files:**
- Create: `docs/phase5-demo.md`
- Modify: `README.md`

Démo :
1. Player déjà appairé (Phase 2)
2. Médias et playlist publiée (Phases 3-4) avec `device_playlists` assigné
3. Au lancement de l'app Player, le PlayerScreen affiche brièvement un loader puis commence à télécharger les médias (visible dans la liste devices : sync_progress monte de 0 à 100)
4. Une fois 100%, la lecture en boucle commence
5. Modifier la playlist dans le back office (ex: changer la durée d'une image), publier (version++)
6. Attendre <15 min OU redémarrer l'app pour forcer le sync immédiat → la nouvelle config s'applique
7. Couper le wifi → la lecture continue depuis le cache
8. Réactiver wifi → un sync se déclenche (si nouvelle version disponible) sinon rien
9. Ajouter une campagne datée passée à un item → après sync, l'item est filtré et n'apparaît plus dans la boucle

Limites :
- **Latence sync max 15 min** (pas de FCM en Phase 5 — différé Phase 5.5)
- **Pas de foreground service** (Phase 5.5) — tablette doit rester au premier plan
- **Pas de resume téléchargement** — un download interrompu redémarre du début (Phase 5.5 si gros médias problématiques)

Commit: `docs(phase5): add phase 5 sync+playback demo script`

---

## Self-Review

1. **Spec coverage** (section 10 Phase 5):
   - ✅ Sync polling-based (FCM différé Phase 5.5, documenté) — Tasks 4-7
   - ✅ App Workmanager-equivalent → Timer.periodic + connectivity listener (Task 8)
   - ✅ Cache SQLite local — Task 2 (drift)
   - ✅ Player plein écran video+image — Task 8
   - ✅ Filtrage par dates `starts_at`/`ends_at` — Task 6
   - ✅ Démo : push back office → tablette télécharge → joue, coupure→continue, retour→rattrape — Task 10
   - ⚠️ Foreground service explicitement reporté Phase 5.5 (acceptable pour démo tablette kiosque)

2. **Type consistency** :
   - `DeviceCredentials` (Phase 2) réutilisé pour authentifier `SyncApiClient`
   - `CachedMediaData` retourne par drift, utilisé par PlayerScreen
   - JWT device a déjà accès aux RLS (verified Phases 2+4)

3. **Dette explicite** :
   - FCM (Phase 5.5)
   - Foreground service (Phase 5.5)
   - Resume téléchargement (Phase 5.5)
   - Heartbeat fréquence fixe à 5 min (config en dur)
   - Pas de retry exponentiel sur échec download

Plan prêt.
