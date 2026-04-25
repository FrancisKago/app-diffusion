import 'package:flutter_test/flutter_test.dart';
import 'package:player/data/local/app_database.dart';
import 'package:player/services/playback_service.dart';

void main() {
  CachedPlaylistItem item(
    String id, {
    int position = 0,
    DateTime? startsAt,
    DateTime? endsAt,
  }) =>
      CachedPlaylistItem(
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
      final items = [item('a'), item('b')];
      expect(PlaybackService.activeItems(items, now), hasLength(2));
    });

    test('drops items before starts_at', () {
      final now = DateTime.utc(2026, 5, 5);
      final items = [
        item('past', startsAt: DateTime.utc(2026, 5, 10)),
        item('current'),
      ];
      final active = PlaybackService.activeItems(items, now);
      expect(active.map((i) => i.id), ['current']);
    });

    test('drops items after ends_at', () {
      final now = DateTime.utc(2026, 5, 5);
      final items = [
        item('expired', endsAt: DateTime.utc(2026, 5, 1)),
        item('current'),
      ];
      final active = PlaybackService.activeItems(items, now);
      expect(active.map((i) => i.id), ['current']);
    });

    test('keeps items where now is exactly between starts_at and ends_at', () {
      final now = DateTime.utc(2026, 5, 5);
      final items = [
        item(
          'in-window',
          startsAt: DateTime.utc(2026, 5, 1),
          endsAt: DateTime.utc(2026, 5, 10),
        ),
      ];
      final active = PlaybackService.activeItems(items, now);
      expect(active.map((i) => i.id), ['in-window']);
    });
  });
}
