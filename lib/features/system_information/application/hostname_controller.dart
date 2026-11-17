import 'package:material_ui/material_ui.dart';

import '../../integration/snapshot_order.dart';

class HostnameController extends ChangeNotifier {
  HostnameController({
    required this.read,
    required this.renameName,
    required this.resolve,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String) renameName;
  final Future<Map<String, dynamic>> Function(String) resolve;
  Map<String, dynamic> value = {};
  String? errorMessage;
  bool _busy = false;
  final _snapshots = SnapshotOrder();
  Future<Map<String, dynamic>> Function()? _retry;
  bool get isBusy => _busy || value['authorizing'] == true;
  bool get hasConflict => value['conflict'] == true;
  String? get staticHostname => value['static_hostname'] as String?;
  String? get hostname => value['hostname'] as String?;
  String? get savedHostname => value['saved_static_hostname'] as String?;
  bool get canRename =>
      value['initialized'] == true &&
      value['writable'] != false &&
      !hasConflict &&
      !isBusy &&
      staticHostname != null;

  Future<void> reload() async {
    if (_busy || _snapshots.disposed) return;
    final current = _snapshots.beginRead();
    try {
      final next = await read();
      if (!current()) return;
      value = next;
      errorMessage = value['error'] as String?;
    } catch (error) {
      if (!current()) return;
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<void> _change(Future<Map<String, dynamic>> Function() action) async {
    if (isBusy || _snapshots.disposed) return;
    _snapshots.invalidate();
    _busy = true;
    notifyListeners();
    try {
      final next = await action();
      if (_snapshots.disposed) return;
      value = next;
      errorMessage = value['error'] as String?;
      _retry = null;
    } catch (error) {
      if (_snapshots.disposed) rethrow;
      _retry = action;
      errorMessage = '$error';
      rethrow;
    } finally {
      _busy = false;
      if (!_snapshots.disposed) notifyListeners();
    }
  }

  Future<void> rename(String name) => _change(() => renameName(name));
  Future<void> useSystemConfiguration() => _change(() => resolve('system'));
  Future<void> applySavedConfiguration() => _change(() => resolve('settings'));
  Future<void> retry() => _retry == null ? reload() : _change(_retry!);

  @override
  void dispose() {
    _snapshots.dispose();
    super.dispose();
  }
}

class HostnameScope extends InheritedNotifier<HostnameController> {
  const HostnameScope({
    super.key,
    required HostnameController controller,
    required super.child,
  }) : super(notifier: controller);
  static HostnameController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HostnameScope>()?.notifier;
}
