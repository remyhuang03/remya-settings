import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../integration/snapshot_order.dart';

class StartupController extends ChangeNotifier {
  StartupController({
    required this.read,
    required this.candidates,
    required this.write,
    required this.resolve,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String) candidates;
  final Future<Map<String, dynamic>> Function(String, Map<String, Object>)
  write;
  final Future<Map<String, dynamic>> Function(String) resolve;
  Map<String, dynamic> value = {};
  String? errorMessage;
  bool isBusy = false;
  bool _readFailed = false;
  final _snapshots = SnapshotOrder();
  bool get hasConflict => value['conflict'] == true;
  bool get canResolve => value['writable'] == true && !_readFailed && !isBusy;
  bool get canChange => canResolve && !hasConflict;
  List<StartupEntry> get entries => [
    for (final entry in value['entries'] as List? ?? const [])
      StartupEntry(entry as Map),
  ];
  String? get disabledReason => isBusy
      ? 'Saving startup apps…'
      : hasConflict
      ? 'Resolve saved and system startup apps before changing them.'
      : !canChange
      ? errorMessage ?? 'Startup configuration is not writable.'
      : null;

  Future<void> reload() => isBusy ? Future.value() : _reload();

  Future<void> _reload() async {
    if (_snapshots.disposed) return;
    final current = _snapshots.beginRead();
    try {
      final next = await read();
      if (!current()) return;
      value = next;
      _readFailed = false;
      errorMessage = value['error'] as String?;
    } catch (error) {
      if (!current()) return;
      _readFailed = true;
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<bool> _change(Future<Map<String, dynamic>> Function() action) async {
    if (isBusy || _snapshots.disposed) return false;
    _snapshots.invalidate();
    isBusy = true;
    notifyListeners();
    String? failure;
    try {
      final next = await action();
      if (!_snapshots.disposed) value = next;
    } catch (error) {
      failure = '$error';
    }
    await _reload();
    if (_snapshots.disposed) return false;
    errorMessage = failure ?? errorMessage;
    isBusy = false;
    notifyListeners();
    return errorMessage == null;
  }

  Future<bool> set(String setting, Map<String, Object> payload) =>
      _change(() => write(setting, payload));
  Future<bool> useSystemConfiguration() => _change(() => resolve('system'));
  Future<bool> applySavedConfiguration() => _change(() => resolve('settings'));

  @override
  void dispose() {
    _snapshots.dispose();
    super.dispose();
  }
}

class StartupScope extends InheritedNotifier<StartupController> {
  const StartupScope({
    super.key,
    required StartupController controller,
    required super.child,
  }) : super(notifier: controller);
  static StartupController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StartupScope>()?.notifier;
}
