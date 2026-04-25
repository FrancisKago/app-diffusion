import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/data/battery_optim_checker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.player/battery_optim');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('isExcluded returns true when native says true', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isExcluded');
      return true;
    });
    final checker = NativeBatteryOptimChecker();
    expect(await checker.isExcluded(), isTrue);
  });

  test('isExcluded defaults to false when native returns null', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    final checker = NativeBatteryOptimChecker();
    expect(await checker.isExcluded(), isFalse);
  });

  test('openExclusionSettings invokes the right method', () async {
    var called = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'openExclusionSettings') {
        called = true;
      }
      return null;
    });
    await NativeBatteryOptimChecker().openExclusionSettings();
    expect(called, isTrue);
  });
}
