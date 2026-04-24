import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('Profile', () {
    const json = {
      'id': '11111111-1111-1111-1111-111111111111',
      'role': 'admin',
      'full_name': 'Alice',
    };

    test('fromJson parses admin profile', () {
      final p = Profile.fromJson(json);
      expect(p.id, '11111111-1111-1111-1111-111111111111');
      expect(p.role, UserRole.admin);
      expect(p.fullName, 'Alice');
    });

    test('toJson produces snake_case', () {
      const p = Profile(
        id: 'x',
        role: UserRole.manager,
        fullName: 'Bob',
      );
      expect(p.toJson(), {
        'id': 'x',
        'role': 'manager',
        'full_name': 'Bob',
      });
    });

    test('equality by value', () {
      const a = Profile(id: 'x', role: UserRole.admin, fullName: 'A');
      const b = Profile(id: 'x', role: UserRole.admin, fullName: 'A');
      expect(a, b);
    });
  });
}
