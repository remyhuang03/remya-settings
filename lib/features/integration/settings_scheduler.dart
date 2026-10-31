import 'dart:async';

/// Independent feature checks run concurrently; overlapping rounds share one future.
class SettingsScheduler {
  SettingsScheduler(this.checks);
  final List<Future<void> Function()> checks;
  Future<void>? _running;
  Timer? _timer;
  bool _disposed = false;

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _running ??= _check().whenComplete(() => _running = null);
  }

  Future<void> _check() =>
      Future.wait([for (final check in checks) _checkFeature(check)]);

  Future<void> _checkFeature(Future<void> Function() check) async {
    // Feature controllers retain their own errors so one failure cannot hide others.
    try {
      await check();
    } catch (_) {}
  }

  void start() {
    _timer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
