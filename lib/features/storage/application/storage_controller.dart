import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../integration/snapshot_order.dart';

class StorageController extends ChangeNotifier {
  StorageController({
    required this.readStorage,
    required this.readCleanup,
    required this.write,
    required this.formatDate,
  });
  final Future<Map<String, dynamic>> Function() readStorage;
  final Future<Map<String, dynamic>> Function() readCleanup;
  final Future<Map<String, dynamic>> Function(String, String) write;
  final Future<String> Function(String) formatDate;
  Map<String, dynamic> storage = {}, cleanup = {};
  String? errorMessage;
  bool _changing = false, _disposed = false;
  final _storageOrder = SnapshotOrder();
  final _cleanupOrder = SnapshotOrder();
  bool get busy =>
      _changing || storage['busy'] == true || cleanup['busy'] == true;
  bool get policyWritable => cleanup['writable'] == true && !busy;
  SnapshotOrder _order(String page) =>
      page == 'storage' ? _storageOrder : _cleanupOrder;

  void apply(String page, Map<String, dynamic> value) {
    if (_disposed) return;
    _order(page).invalidate();
    if (page == 'storage') {
      storage = value;
    } else {
      cleanup = value;
    }
    errorMessage = value['error'] as String?;
    notifyListeners();
  }

  Future<void> reload() => _changing || _disposed ? Future.value() : _reload();

  Future<void> _reload() async {
    if (_disposed) return;
    final storageCurrent = _storageOrder.beginRead();
    final cleanupCurrent = _cleanupOrder.beginRead();
    try {
      final values = await Future.wait([readStorage(), readCleanup()]);
      if (!storageCurrent() && !cleanupCurrent()) return;
      if (storageCurrent()) storage = values[0];
      if (cleanupCurrent()) cleanup = values[1];
      errorMessage = storage['error'] as String? ?? cleanup['error'] as String?;
    } catch (error) {
      if (!storageCurrent() && !cleanupCurrent()) return;
      errorMessage = '$error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> change(String id, Object payload) async {
    if (busy || _disposed) return false;
    _storageOrder.invalidate();
    _cleanupOrder.invalidate();
    _changing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final page = id.startsWith('storage.') ? 'storage' : 'cleanup';
      var value = await write(id, jsonEncode(payload));
      final elapsed = Stopwatch()..start();
      while (value['busy'] == true) {
        if (elapsed.elapsed > const Duration(minutes: 5)) {
          throw StateError(
            'The storage operation is still running; check its status before retrying',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_disposed) return false;
        final current = _order(page).beginRead();
        final next = await (page == 'storage' ? readStorage() : readCleanup());
        if (_disposed) return false;
        if (current()) apply(page, next);
        value = page == 'storage' ? storage : cleanup;
      }
      if (value['error'] case final String error) throw StateError(error);
      await _reload();
      return true;
    } catch (error) {
      errorMessage = '$error';
      return false;
    } finally {
      _changing = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _storageOrder.dispose();
    _cleanupOrder.dispose();
    super.dispose();
  }
}

class StorageScope extends InheritedNotifier<StorageController> {
  const StorageScope({
    super.key,
    required StorageController controller,
    required super.child,
  }) : super(notifier: controller);
  static StorageController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StorageScope>()?.notifier;
}
