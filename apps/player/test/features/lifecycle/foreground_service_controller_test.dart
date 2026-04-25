import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lifecycle/application/foreground_service_controller.dart';

class _FakeIsRunning {
  bool value = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('start() is a no-op if already running', () async {
    final state = _FakeIsRunning()..value = true;
    var startCount = 0;
    final controller = ForegroundServiceController(
      isRunningProbe: () async => state.value,
      starter: () async {
        startCount++;
        state.value = true;
        return const ServiceRequestSuccess();
      },
      stopper: () async {
        state.value = false;
        return const ServiceRequestSuccess();
      },
    );
    await controller.start();
    expect(startCount, 0);
  });

  test('start() invokes starter when not running', () async {
    final state = _FakeIsRunning()..value = false;
    var startCount = 0;
    final controller = ForegroundServiceController(
      isRunningProbe: () async => state.value,
      starter: () async {
        startCount++;
        state.value = true;
        return const ServiceRequestSuccess();
      },
      stopper: () async {
        state.value = false;
        return const ServiceRequestSuccess();
      },
    );
    await controller.start();
    expect(startCount, 1);
  });

  test('stop() invokes stopper', () async {
    final state = _FakeIsRunning()..value = true;
    var stopCount = 0;
    final controller = ForegroundServiceController(
      isRunningProbe: () async => state.value,
      starter: () async => const ServiceRequestSuccess(),
      stopper: () async {
        stopCount++;
        state.value = false;
        return const ServiceRequestSuccess();
      },
    );
    await controller.stop();
    expect(stopCount, 1);
  });
}
