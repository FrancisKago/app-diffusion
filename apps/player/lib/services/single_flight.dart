/// Coalesces concurrent invocations of an async action into one run at a
/// time.
///
/// The player's sync has three independent triggers (15-min timer,
/// connectivity listener, FCM push). Without a guard they could run
/// concurrently and race on the same `.part` download files. With this
/// guard, calls made while a run is in flight coalesce: the latest queued
/// action runs exactly once after the current run finishes (state may have
/// changed, so one follow-up — not N).
class SingleFlight {
  Future<void>? _running;
  Future<void> Function()? _pending;

  Future<void> run(Future<void> Function() action) {
    final running = _running;
    if (running != null) {
      _pending = action;
      return running;
    }
    final future = _loop(action);
    _running = future;
    return future;
  }

  Future<void> _loop(Future<void> Function() first) async {
    var action = first;
    try {
      while (true) {
        await action();
        final next = _pending;
        if (next == null) break;
        _pending = null;
        action = next;
      }
    } finally {
      _running = null;
      _pending = null;
    }
  }
}
