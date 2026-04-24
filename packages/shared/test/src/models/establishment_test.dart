import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Establishment', () {
    test('fromJson parses required fields and timezone', () {
      final e = Establishment.fromJson({
        'id': 'e1',
        'name': 'Lounge Plateau',
        'timezone': 'Africa/Yaounde',
      });
      expect(e.id, 'e1');
      expect(e.name, 'Lounge Plateau');
      expect(e.timezone, 'Africa/Yaounde');
    });

    test('defaults timezone to UTC when missing', () {
      final e = Establishment.fromJson({'id': 'e1', 'name': 'Resto'});
      expect(e.timezone, 'UTC');
    });
  });
}
