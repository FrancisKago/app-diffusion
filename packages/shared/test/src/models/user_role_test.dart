import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('UserRole', () {
    test('fromString parses admin', () {
      expect(UserRole.fromString('admin'), UserRole.admin);
    });

    test('fromString parses manager', () {
      expect(UserRole.fromString('manager'), UserRole.manager);
    });

    test('fromString throws on unknown', () {
      expect(
        () => UserRole.fromString('pirate'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('dbValue returns lowercase snake', () {
      expect(UserRole.admin.dbValue, 'admin');
      expect(UserRole.manager.dbValue, 'manager');
    });
  });
}
