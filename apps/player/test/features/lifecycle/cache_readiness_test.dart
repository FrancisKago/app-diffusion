import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/application/cache_readiness.dart';

void main() {
  bool existsAll(String _) => true;
  bool existsNone(String _) => false;

  group('computeCacheReadiness', () {
    test('empty playlist → not ready, nothing missing', () {
      final r = computeCacheReadiness(const [], existsAll);
      expect(r.total, 0);
      expect(r.downloaded, 0);
      expect(r.missing, isEmpty);
      expect(r.isReady, isFalse);
    });

    test('all media present on disk → ready', () {
      final r = computeCacheReadiness(
        const [
          MediaRef(filename: 'a.mp4', localPath: '/m/a.mp4'),
          MediaRef(filename: 'b.mp4', localPath: '/m/b.mp4'),
        ],
        existsAll,
      );
      expect(r.total, 2);
      expect(r.downloaded, 2);
      expect(r.missing, isEmpty);
      expect(r.isReady, isTrue);
    });

    test('null localPath counts as missing', () {
      final r = computeCacheReadiness(
        const [MediaRef(filename: 'a.mp4', localPath: null)],
        existsAll,
      );
      expect(r.downloaded, 0);
      expect(r.missing, ['a.mp4']);
      expect(r.isReady, isFalse);
    });

    test('localPath set but file absent counts as missing', () {
      final r = computeCacheReadiness(
        const [MediaRef(filename: 'gone.mp4', localPath: '/m/gone.mp4')],
        existsNone,
      );
      expect(r.downloaded, 0);
      expect(r.missing, ['gone.mp4']);
    });

    test('partial readiness reports exactly the missing filenames', () {
      final r = computeCacheReadiness(
        [
          const MediaRef(filename: 'have.mp4', localPath: '/m/have.mp4'),
          const MediaRef(filename: 'missing.mp4', localPath: '/m/missing.mp4'),
        ],
        (path) => path == '/m/have.mp4',
      );
      expect(r.total, 2);
      expect(r.downloaded, 1);
      expect(r.missing, ['missing.mp4']);
      expect(r.isReady, isFalse);
    });
  });
}
