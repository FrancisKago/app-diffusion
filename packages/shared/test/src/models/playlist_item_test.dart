import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('PlaylistItem', () {
    final json = {
      'id': 'pi1',
      'playlist_id': 'p1',
      'media_id': 'm1',
      'position': 0,
      'display_duration_sec': 15,
      'starts_at': null,
      'ends_at': null,
    };

    test('fromJson minimal', () {
      final pi = PlaylistItem.fromJson(json);
      expect(pi.id, 'pi1');
      expect(pi.playlistId, 'p1');
      expect(pi.mediaId, 'm1');
      expect(pi.position, 0);
      expect(pi.displayDurationSec, 15);
      expect(pi.startsAt, isNull);
      expect(pi.endsAt, isNull);
    });

    test('fromJson with campaign dates', () {
      final j = {
        ...json,
        'starts_at': '2026-05-01T00:00:00.000Z',
        'ends_at': '2026-05-07T23:59:59.000Z',
      };
      final pi = PlaylistItem.fromJson(j);
      expect(pi.startsAt, isNotNull);
      expect(pi.endsAt, isNotNull);
      expect(pi.startsAt!.isBefore(pi.endsAt!), isTrue);
    });

    test('toJson roundtrip preserves snake_case', () {
      final pi = PlaylistItem.fromJson(json);
      final j = pi.toJson();
      expect(j['playlist_id'], 'p1');
      expect(j['media_id'], 'm1');
      expect(j['display_duration_sec'], 15);
      expect(j['position'], 0);
    });
  });
}
