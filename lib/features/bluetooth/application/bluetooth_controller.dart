import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

class BluetoothController extends ChangeNotifier {
  BluetoothController({required this.read, required this.write});
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String, String) write;
  Map<String, dynamic> value = {};
  String? selectedAdapter;
  String? errorMessage;
  bool sending = false;
  bool _disposed = false;

  List<Map> get adapters => (value['adapters'] as List? ?? []).cast<Map>();
  Map? get adapter =>
      adapters.where((a) => a['id'] == selectedAdapter).firstOrNull ??
      adapters.firstOrNull;
  List<Map> get devices => (value['devices'] as List? ?? [])
      .cast<Map>()
      .where((d) => d['adapter'] == adapter?['id'])
      .toList();
  bool get available => value['available'] == true;
  bool get powered => adapter?['powered'] == true;
  Map? get operation => value['operation'] as Map?;
  Map? get prompt => value['prompt'] as Map?;
  bool get busy => sending || operation?['status'] == 'running';
  bool get pairing =>
      operation?['status'] == 'running' && operation?['kind'] == 'pair';
  bool get scanning =>
      (value['scanning'] as List? ?? []).contains(adapter?['id']);

  void apply(Map<String, dynamic> state) {
    if (_disposed) return;
    value = state;
    errorMessage = state['error'] as String?;
    notifyListeners();
  }

  Future<void> reload() async {
    try {
      apply(await read());
    } catch (error) {
      if (!_disposed) {
        errorMessage = '$error';
        notifyListeners();
      }
    }
  }

  void selectAdapter(String id) {
    if (busy) return;
    release();
    selectedAdapter = id;
    notifyListeners();
  }

  Future<void> set(String id, [Map<String, dynamic> request = const {}]) async {
    if (_disposed) return;
    sending = true;
    notifyListeners();
    try {
      apply(
        await write(id, jsonEncode({'adapter': ?adapter?['id'], ...request})),
      );
    } catch (error) {
      if (!_disposed) {
        errorMessage = '$error';
      }
    } finally {
      sending = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> device(String id, Map device) =>
      set(id, {'device': device['id'], 'adapter': device['adapter']});
  Future<void> scan({bool visible = false}) => set(
    visible ? bluetoothDiscoverableSettingId : bluetoothScanSettingId,
    {'enabled': true},
  );
  Future<void> release() async {
    // Cancel and stop are allowed while Pair is waiting for an Agent response.
    final adapterId = adapter?['id'];
    if (pairing) await set(bluetoothCancelSettingId);
    if (adapterId != null) {
      await set(bluetoothScanSettingId, {
        'adapter': adapterId,
        'enabled': false,
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class BluetoothScope extends InheritedNotifier<BluetoothController> {
  const BluetoothScope({
    super.key,
    required BluetoothController controller,
    required super.child,
  }) : super(notifier: controller);
  static BluetoothController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BluetoothScope>()?.notifier;
}
