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
      expect(d.establishmentId, 'e1');
      expect(d.name, 'Écran terrasse');
      expect(d.orientation, DeviceOrientation.landscape);
    });

    test('fromJson parses portrait device', () {
      final d = Device.fromJson({
        'id': 'd1',
        'establishment_id': 'e1',
        'name': 'X',
        'orientation': 'portrait',
      });
      expect(d.orientation, DeviceOrientation.portrait);
    });

    test('fromJson defaults orientation to landscape when missing', () {
      final d = Device.fromJson({
        'id': 'd1',
        'establishment_id': 'e1',
        'name': 'X',
      });
      expect(d.orientation, DeviceOrientation.landscape);
    });
  });
}
