import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:player/data/local/app_database.dart';
import 'package:player/data/local/cache_storage.dart';
import 'package:player/data/media_downloader.dart';
import 'package:player/data/remote/sync_api_client.dart';
import 'package:player/data/sync_service.dart';

class _MockApi extends Mock implements SyncApiClient {}

class _MockStorage extends Mock implements CacheStorage {}

class _MockDownloader extends Mock implements MediaDownloader {}

void main() {
  late AppDatabase db;
  late _MockApi api;
  late _MockStorage storage;
  late SyncService sync;

  setUpAll(() {
    registerFallbackValue(<String>{});
  });

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    api = _MockApi();
    storage = _MockStorage();
    when(() => storage.purgeLruIfNeeded(any())).thenAnswer((_) async => 0);
    sync = SyncService(
      api: api,
      db: db,
      storage: storage,
      deviceId: 'device-1',
      downloader: _MockDownloader(),
    );
  });

  tearDown(() => db.close());

  Future<void> seedPlaylist(String id) async {
    await db.upsertPlaylist(
      CachedPlaylistCompanion(
        id: Value(id),
        establishmentId: const Value('e1'),
        name: Value('Playlist $id'),
      ),
    );
    await db.replaceItems(id, [
      CachedPlaylistItemsCompanion(
        id: Value('$id-item-0'),
        playlistId: Value(id),
        mediaId: const Value('media-0'),
        position: const Value(0),
      ),
    ]);
  }

  test('unassignment clears the local playlist cache (standby, not stale loop)',
      () async {
    await seedPlaylist('A');
    when(() => api.getMyDevicePlaylistAssignment('device-1'))
        .thenAnswer((_) async => null);

    final result = await sync.sync();

    expect(result, isNull);
    expect(await db.getPlaylist('A'), isNull);
    expect(await db.itemsFor('A'), isEmpty);
  });

  test('reassignment purges the previously cached playlist', () async {
    await seedPlaylist('A');
    when(() => api.getMyDevicePlaylistAssignment('device-1'))
        .thenAnswer((_) async => 'B');
    when(() => api.fetchPlaylist('B')).thenAnswer(
      (_) async => {
        'id': 'B',
        'establishment_id': 'e1',
        'name': 'Playlist B',
        'version': 3,
        'audio_enabled': false,
        'published_at': null,
      },
    );
    when(() => api.fetchPlaylistItems('B')).thenAnswer((_) async => []);
    when(() => api.fetchMedia(any())).thenAnswer((_) async => []);

    final result = await sync.sync();

    expect(result, isNotNull);
    expect(result!.playlistVersion, 3);
    expect(await db.getPlaylist('A'), isNull, reason: 'stale playlist purged');
    expect(await db.itemsFor('A'), isEmpty);
    expect(await db.getPlaylist('B'), isNotNull);
  });
}
