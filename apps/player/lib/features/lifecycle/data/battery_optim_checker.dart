import 'package:flutter/services.dart';

abstract class BatteryOptimChecker {
  Future<bool> isExcluded();
  Future<void> openExclusionSettings();
}

class NativeBatteryOptimChecker implements BatteryOptimChecker {
  static const _channel = MethodChannel('app.player/battery_optim');

  @override
  Future<bool> isExcluded() async {
    final result = await _channel.invokeMethod<bool>('isExcluded');
    return result ?? false;
  }

  @override
  Future<void> openExclusionSettings() async {
    await _channel.invokeMethod<void>('openExclusionSettings');
  }
}
