import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  group('AppException', () {
    test('stores message and optional cause', () {
      final e = AppException('boom', cause: 'detail');
      expect(e.message, 'boom');
      expect(e.cause, 'detail');
      expect(e.toString(), contains('boom'));
    });

    test('toString without cause', () {
      final e = AppException('boom');
      expect(e.toString(), 'AppException: boom');
    });
  });
}
