import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

void main() {
  test('AdminDiagnostic copyWith works', () {
    const d = AdminDiagnostic(
      appVersion: '0.1.0',
      deviceId: 'd1',
      foregroundServiceRunning: false,
      batteryOptimExcluded: false,
    );
    final d2 = d.copyWith(batteryOptimExcluded: true);
    expect(d2.batteryOptimExcluded, isTrue);
    expect(d2.deviceId, 'd1');
  });

  test('AdminDiagnostic equality', () {
    const a = AdminDiagnostic(
      appVersion: '0.1.0',
      deviceId: 'd1',
      foregroundServiceRunning: true,
      batteryOptimExcluded: true,
    );
    const b = AdminDiagnostic(
      appVersion: '0.1.0',
      deviceId: 'd1',
      foregroundServiceRunning: true,
      batteryOptimExcluded: true,
    );
    expect(a, equals(b));
  });
}
