import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Device', () {
    test('fromJson parses landscape device', () {
      final d = Device.fromJson({
        'id': 'd1',
        'establishment_id': 'e1',
        'name': 'Écran terrasse',
        'orientation': 'landscape',
      });
      expect(d.id, 'd1');
      expect(d.orientation, DeviceOrientation.landscape);
      expect(d.lastSeenAt, isNull);
      expect(d.syncProgress, isNull);
    });

    test('fromJson defaults orientation to landscape when missing', () {
      final d = Device.fromJson({
        'id': 'd1',
        'establishment_id': 'e1',
        'name': 'X',
      });
      expect(d.orientation, DeviceOrientation.landscape);
    });

    test('fromJson parses last_seen_at and sync_progress', () {
      final d = Device.fromJson({
        'id': 'd1',
        'establishment_id': 'e1',
        'name': 'X',
        'orientation': 'landscape',
        'last_seen_at': '2026-04-25T10:30:00.000Z',
        'sync_progress': 75,
      });
      expect(d.lastSeenAt, isNotNull);
      expect(d.syncProgress, 75);
    });
  });
}
