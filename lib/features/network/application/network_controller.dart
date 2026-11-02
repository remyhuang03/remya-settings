import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

const _permissionPrefix = 'org.freedesktop.NetworkManager.';

class NetworkController extends ChangeNotifier {
  NetworkController({
    required this.read,
    required this.write,
    required this.resolve,
    required this.formatDate,
    required this.readTraffic,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String, String) write;
  final Future<Map<String, dynamic>> Function(String) resolve;
  final Future<String> Function(String) formatDate;
  final Future<Map<String, dynamic>> Function() readTraffic;
  Map<String, dynamic> value = {};
  String? errorMessage;
  bool isBusy = false;

  bool get isAvailable => value['available'] == true;
  bool get hasConflict => value['conflict'] == true;
  bool get canChangePreferences =>
      value['writable'] == true && !hasConflict && !isBusy;
  bool get wifiEnabled => value['wifi_enabled'] == true;
  bool get wifiHardwareEnabled => value['wifi_hardware_enabled'] == true;
  String get connectivity => value['connectivity'] as String? ?? 'unknown';
  bool get connectivityChecked => value['connectivity_check'] == true;
  bool get canSignIn => connectivity == 'portal' && value['check_uri'] != null;
  String? get connecting => value['connecting'] as String?;
  String? get adapter => value['adapter'] as String?;
  Map? get failure => value['failure'] as Map?;
  List<Map> get conflicts => (value['conflicts'] as List? ?? []).cast<Map>();
  List<Map> get profiles => (value['profiles'] as List? ?? []).cast<Map>();
  List<Map> get devices => (value['devices'] as List? ?? []).cast<Map>();
  List<Map> get wifiAdapters =>
      devices.where((d) => d['kind'] == 'wifi').toList();
  Map? get wifiAdapter =>
      wifiAdapters.where((d) => d['interface'] == adapter).firstOrNull;
  List<Map> get networks =>
      (wifiAdapter?['networks'] as List? ?? []).cast<Map>();
  Map? get currentNetwork =>
      networks.where((n) => n['in_use'] == true).firstOrNull;
  Map? get primaryDevice {
    final uuid = value['primary_uuid'];
    if (uuid == null) return null;
    return devices.where((d) => d['uuid'] == uuid).firstOrNull;
  }

  /// False only when the system refuses outright; `auth` asks through polkit.
  bool allowed(String permission) =>
      (value['permissions'] as Map?)?['$_permissionPrefix$permission'] != 'no';

  String get conflictSummary =>
      [for (final conflict in conflicts) conflict['name'] as String].join('\n');

  /// A `Changed` signal already carries the fresh state.
  void apply(Map<String, dynamic> state) {
    value = state;
    errorMessage = state['error'] as String?;
    notifyListeners();
  }

  Future<void> reload() async {
    try {
      apply(await read());
    } catch (error) {
      errorMessage = '$error';
      notifyListeners();
    }
  }

  Future<void> _change(Future<Map<String, dynamic>> Function() action) async {
    if (isBusy) return;
    isBusy = true;
    notifyListeners();
    String? failed;
    try {
      value = await action();
    } catch (error) {
      failed = '$error';
    }
    await reload();
    errorMessage = failed ?? errorMessage;
    isBusy = false;
    notifyListeners();
  }

  Future<void> set(String id, String setting) =>
      _change(() => write(id, setting));

  /// Background refresh: a rejected scan must not replace visible results or errors.
  Future<void> scan() async {
    if (isBusy || !wifiEnabled || wifiAdapter == null) return;
    try {
      await write(wifiRefreshSettingId, 'scan');
    } catch (_) {
      await reload();
    }
  }

  Future<void> useSystemConfiguration() => _change(() => resolve('system'));
  Future<void> applySavedConfiguration() => _change(() => resolve('settings'));
}

class NetworkScope extends InheritedNotifier<NetworkController> {
  const NetworkScope({
    super.key,
    required NetworkController controller,
    required super.child,
  }) : super(notifier: controller);
  static NetworkController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NetworkScope>()?.notifier;
}
