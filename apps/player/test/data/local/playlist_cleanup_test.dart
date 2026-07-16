import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/data/local/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> seedPlaylist(String id, {int items = 1}) async {
    await db.upsertPlaylist(
      CachedPlaylistCompanion(
        id: Value(id),
        establishmentId: const Value('e1'),
        name: Value('Playlist $id'),
      ),
    );
    await db.replaceItems(id, [
      for (var i = 0; i < items; i++)
        CachedPlaylistItemsCompanion(
          id: Value('$id-item-$i'),
          playlistId: Value(id),
          mediaId: Value('media-$i'),
          position: Value(i),
        ),
    ]);
  }

  test('purgePlaylistsExcept drops other playlists and their items', () async {
    await seedPlaylist('A', items: 2);
    await seedPlaylist('B', items: 1);

    await db.purgePlaylistsExcept('B');

    expect(await db.getPlaylist('A'), isNull);
    expect(await db.getPlaylist('B'), isNotNull);
    expect(await db.itemsFor('A'), isEmpty);
    expect((await db.itemsFor('B')).length, 1);
  });

  test('purgePlaylistsExcept is a no-op when only the kept playlist exists',
      () async {
    await seedPlaylist('B', items: 3);
    await db.purgePlaylistsExcept('B');
    expect(await db.getPlaylist('B'), isNotNull);
    expect((await db.itemsFor('B')).length, 3);
  });

  test('clearPlaylists empties playlists and items', () async {
    await seedPlaylist('A');
    await seedPlaylist('B');

    await db.clearPlaylists();

    expect(await db.getPlaylist('A'), isNull);
    expect(await db.getPlaylist('B'), isNull);
    expect(await db.itemsFor('A'), isEmpty);
    expect(await db.itemsFor('B'), isEmpty);
  });
}
