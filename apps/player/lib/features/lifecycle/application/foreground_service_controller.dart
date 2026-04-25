import 'package:flutter_foreground_task/flutter_foreground_task.dart';

typedef IsRunningProbe = Future<bool> Function();
typedef ServiceStarter = Future<ServiceRequestResult> Function();
typedef ServiceStopper = Future<ServiceRequestResult> Function();

/// Thin Dart wrapper around [FlutterForegroundTask] start/stop, with
/// idempotent semantics and dependency injection for tests.
class ForegroundServiceController {
  ForegroundServiceController({
    IsRunningProbe? isRunningProbe,
    ServiceStarter? starter,
    ServiceStopper? stopper,
  })  : _isRunningProbe = isRunningProbe ?? _defaultIsRunningProbe,
        _starter = starter ?? _defaultStarter,
        _stopper = stopper ?? _defaultStopper;

  final IsRunningProbe _isRunningProbe;
  final ServiceStarter _starter;
  final ServiceStopper _stopper;

  Future<void> start() async {
    if (await _isRunningProbe()) return;
    await _starter();
  }

  Future<void> stop() async {
    await _stopper();
  }

  Future<bool> isRunning() => _isRunningProbe();

  static Future<bool> _defaultIsRunningProbe() =>
      FlutterForegroundTask.isRunningService;

  static Future<ServiceRequestResult> _defaultStarter() {
    return FlutterForegroundTask.startService(
      serviceId: 7421,
      notificationTitle: 'App de diffusion',
      notificationText: 'Lecture en cours',
    );
  }

  static Future<ServiceRequestResult> _defaultStopper() =>
      FlutterForegroundTask.stopService();
}
