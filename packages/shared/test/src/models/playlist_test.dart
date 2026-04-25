import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Playlist', () {
    final json = {
      'id': 'p1',
      'establishment_id': 'e1',
      'name': 'Playlist principale',
      'is_default': true,
      'audio_enabled': false,
      'version': 3,
      'published_at': '2026-04-25T10:00:00.000Z',
    };

    test('fromJson parses all fields', () {
      final p = Playlist.fromJson(json);
      expect(p.id, 'p1');
      expect(p.establishmentId, 'e1');
      expect(p.name, 'Playlist principale');
      expect(p.isDefault, true);
      expect(p.audioEnabled, false);
      expect(p.version, 3);
      expect(p.publishedAt, isNotNull);
      expect(p.publishedAt!.toUtc().year, 2026);
    });

    test('fromJson with null published_at', () {
      final p = Playlist.fromJson({...json, 'published_at': null});
      expect(p.publishedAt, isNull);
    });

    test('toJson roundtrip preserves snake_case', () {
      final p = Playlist.fromJson(json);
      final j = p.toJson();
      expect(j['establishment_id'], 'e1');
      expect(j['is_default'], true);
      expect(j['audio_enabled'], false);
      expect(j['version'], 3);
    });
  });
}
