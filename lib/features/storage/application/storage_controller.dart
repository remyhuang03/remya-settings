import 'dart:convert';

import 'package:material_ui/material_ui.dart';

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
  bool get busy =>
      _changing || storage['busy'] == true || cleanup['busy'] == true;
  bool get policyWritable => cleanup['writable'] == true && !busy;
  void apply(String page, Map<String, dynamic> value) {
    if (_disposed) return;
    if (page == 'storage') {
      storage = value;
    } else {
      cleanup = value;
    }
    errorMessage = value['error'] as String?;
    notifyListeners();
  }

  Future<void> reload() async {
    try {
      final values = await Future.wait([readStorage(), readCleanup()]);
      if (_disposed) return;
      storage = values[0];
      cleanup = values[1];
      errorMessage = storage['error'] as String? ?? cleanup['error'] as String?;
    } catch (error) {
      errorMessage = '$error';
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> change(String id, Object payload) async {
    if (busy) return false;
    _changing = true;
    errorMessage = null;
    notifyListeners();
    try {
      final page = id.startsWith('storage.') ? 'storage' : 'cleanup';
      var value = await write(id, jsonEncode(payload));
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (value['busy'] == true) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError(
            'The storage operation is still running; check its status before retrying',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        value = await (page == 'storage' ? readStorage() : readCleanup());
        if (_disposed) return false;
        apply(page, value);
      }
      if (value['error'] case final String error) throw StateError(error);
      await reload();
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
