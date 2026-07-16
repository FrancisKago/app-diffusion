import 'package:backoffice/features/media/data/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> baseRow({List<dynamic>? items}) => {
        'id': 'm1',
        'establishment_id': 'e1',
        'type': 'video',
        'file_path': 'e1/m1.mp4',
        'file_size': 123,
        'mime_type': 'video/mp4',
        'checksum_sha256': 'abc',
        'original_filename': 'clip.mp4',
        if (items != null) 'playlist_items': items,
      };

  group('MediaWithUsage.fromRow', () {
    test('no playlist_items → unused, count 0', () {
      final u = MediaWithUsage.fromRow(baseRow(items: const []));
      expect(u.isUnused, isTrue);
      expect(u.usageCount, 0);
      expect(u.playlistNames, isEmpty);
      expect(u.media.id, 'm1');
    });

    test('missing playlist_items key → unused', () {
      final u = MediaWithUsage.fromRow(baseRow());
      expect(u.isUnused, isTrue);
    });

    test('counts distinct playlists, sorted', () {
      final u = MediaWithUsage.fromRow(
        baseRow(items: [
          {
            'playlist_id': 'p2',
            'playlists': {'name': 'Soir'},
          },
          {
            'playlist_id': 'p1',
            'playlists': {'name': 'Matin'},
          },
        ]),
      );
      expect(u.usageCount, 2);
      expect(u.playlistNames, ['Matin', 'Soir']);
      expect(u.isUnused, isFalse);
    });

    test('same media twice in one playlist counts the playlist once', () {
      final u = MediaWithUsage.fromRow(
        baseRow(items: [
          {
            'playlist_id': 'p1',
            'playlists': {'name': 'Matin'},
          },
          {
            'playlist_id': 'p1',
            'playlists': {'name': 'Matin'},
          },
        ]),
      );
      expect(u.usageCount, 1);
      expect(u.playlistNames, ['Matin']);
    });

    test('tolerates a null/absent nested playlists object', () {
      final u = MediaWithUsage.fromRow(
        baseRow(items: [
          {'playlist_id': 'p1', 'playlists': null},
        ]),
      );
      // A dangling item with no readable playlist name still marks the media
      // as used (count by playlist_id) so it is not silently mass-deleted.
      expect(u.isUnused, isFalse);
      expect(u.usageCount, 1);
      expect(u.playlistNames, isEmpty);
    });
  });
}
