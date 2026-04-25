import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Media', () {
    final fullJson = {
      'id': 'm1',
      'establishment_id': 'e1',
      'owner_id': 'u1',
      'type': 'video',
      'file_path': 'e1/m1.mp4',
      'file_size': 5242880,
      'duration_sec': 30,
      'width': 1920,
      'height': 1080,
      'mime_type': 'video/mp4',
      'checksum_sha256': 'deadbeef',
      'original_filename': 'clip.mp4',
    };

    test('fromJson parses video', () {
      final m = Media.fromJson(fullJson);
      expect(m.id, 'm1');
      expect(m.type, MediaType.video);
      expect(m.durationSec, 30);
      expect(m.fileSize, 5242880);
      expect(m.establishmentId, 'e1');
    });

    test('fromJson parses image without duration', () {
      final j = {...fullJson, 'type': 'image', 'duration_sec': null};
      final m = Media.fromJson(j);
      expect(m.type, MediaType.image);
      expect(m.durationSec, isNull);
    });

    test('toJson roundtrip preserves snake_case keys', () {
      final m = Media.fromJson(fullJson);
      final j = m.toJson();
      expect(j['type'], 'video');
      expect(j['file_size'], 5242880);
      expect(j['duration_sec'], 30);
      expect(j['establishment_id'], 'e1');
      expect(j['file_path'], 'e1/m1.mp4');
      expect(j['mime_type'], 'video/mp4');
      expect(j['checksum_sha256'], 'deadbeef');
      expect(j['original_filename'], 'clip.mp4');
    });
  });
}
