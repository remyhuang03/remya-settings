import 'package:material_ui/material_ui.dart';

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
    try {
      value = await read();
      errorMessage = value['error'] as String?;
    } catch (error) {
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<void> _change(Future<Map<String, dynamic>> Function() action) async {
    if (isBusy) return;
    _busy = true;
    notifyListeners();
    try {
      value = await action();
      errorMessage = value['error'] as String?;
      _retry = null;
    } catch (error) {
      _retry = action;
      errorMessage = '$error';
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> rename(String name) => _change(() => renameName(name));
  Future<void> useSystemConfiguration() => _change(() => resolve('system'));
  Future<void> applySavedConfiguration() => _change(() => resolve('settings'));
  Future<void> retry() => _retry == null ? reload() : _change(_retry!);
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
