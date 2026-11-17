/// Lets a controller discard stale reads and errors after a newer operation.
class SnapshotOrder {
  int _generation = 0;
  bool _disposed = false;

  bool get disposed => _disposed;

  bool Function() beginRead() {
    final generation = ++_generation;
    return () => !_disposed && generation == _generation;
  }

  void invalidate() => _generation++;
  void dispose() => _disposed = true;
}
