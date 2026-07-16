import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/services/single_flight.dart';

void main() {
  test('runs the action when idle', () async {
    final flight = SingleFlight();
    var runs = 0;
    await flight.run(() async => runs++);
    expect(runs, 1);
  });

  test('concurrent calls do not run the action in parallel', () async {
    final flight = SingleFlight();
    var active = 0;
    var maxActive = 0;
    Future<void> action() async {
      active++;
      if (active > maxActive) maxActive = active;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      active--;
    }

    await Future.wait([
      flight.run(action),
      flight.run(action),
      flight.run(action),
    ]);
    expect(maxActive, 1);
  });

  test('a call made during a run schedules exactly one follow-up run',
      () async {
    final flight = SingleFlight();
    var runs = 0;
    final firstStarted = Completer<void>();
    final release = Completer<void>();

    final first = flight.run(() async {
      runs++;
      firstStarted.complete();
      await release.future;
    });
    await firstStarted.future;

    // Three triggers while the first run is still in flight...
    final second = flight.run(() async => runs++);
    final third = flight.run(() async => runs++);
    final fourth = flight.run(() async => runs++);
    release.complete();
    await Future.wait([first, second, third, fourth]);

    // ...coalesce into a single follow-up run.
    expect(runs, 2);
  });

  test('a failing run releases the lock for the next call', () async {
    final flight = SingleFlight();
    await expectLater(
      flight.run(() async => throw StateError('boom')),
      throwsStateError,
    );
    var runs = 0;
    await flight.run(() async => runs++);
    expect(runs, 1);
  });
}
