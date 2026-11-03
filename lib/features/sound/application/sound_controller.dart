import 'dart:convert';

import 'package:material_ui/material_ui.dart';

class SoundController extends ChangeNotifier {
  SoundController({
    required this.read,
    required this.write,
    required this.resolve,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String, String) write;
  final Future<Map<String, dynamic>> Function(String) resolve;
  Map<String, dynamic> value = {};
  String? errorMessage;
  bool isBusy = false;
  bool _disposed = false;
  bool _reading = false;
  int _revision = 0;

  Map get system => value['system'] as Map? ?? const {};
  List<Map> get devices => (system['devices'] as List? ?? []).cast<Map>();
  List<Map> get streams => (system['streams'] as List? ?? []).cast<Map>();
  bool get available => value['available'] == true;
  bool get hasConflict => value['conflict'] == true;
  bool get canChange =>
      available &&
      value['initialized'] == true &&
      !hasConflict &&
      !isBusy &&
      errorMessage == null;
  List<Map> devicesFor(String direction) =>
      devices.where((d) => d['direction'] == direction).toList();
  Map? selected(String direction) =>
      devicesFor(direction)
          .where((d) => d['name'] == system['default_$direction'])
          .firstOrNull;
  static double volume(Map item) {
    final channels = (item['preferences'] as Map)['channels'] as List;
    final maximum = channels.cast<num>().fold<num>(0, (a, b) => a > b ? a : b);
    return maximum * 100 / 65536;
  }

  static bool muted(Map item) => (item['preferences'] as Map)['muted'] == true;

  void apply(Map<String, dynamic> state) {
    if (_disposed) return;
    value = state;
    errorMessage = state['error'] as String?;
    notifyListeners();
  }

  Future<void> reload() async {
    if (isBusy || _reading) return;
    _reading = true;
    final revision = _revision;
    try {
      final result = await read();
      if (revision == _revision) apply(result);
    } catch (e) {
      if (!_disposed && revision == _revision) {
        errorMessage = '$e';
        notifyListeners();
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _attempt(Future<Map<String, dynamic>> Function() action) async {
    if (_disposed || isBusy) return;
    isBusy = true;
    _revision++;
    errorMessage = null;
    notifyListeners();
    try {
      apply(await action());
    } catch (e) {
      try {
        apply(await read());
      } catch (_) {}
      if (!_disposed) errorMessage = '$e';
    } finally {
      if (!_disposed) {
        isBusy = false;
        notifyListeners();
      }
    }
  }

  Future<void> set(String id, Map<String, Object?> request) =>
      _attempt(() => write(id, jsonEncode(request)));
  Future<void> refresh() => _attempt(() => write('sound.refresh', '{}'));
  Future<void> useSystemConfiguration() => _attempt(() => resolve('system'));
  Future<void> applySavedConfiguration() => _attempt(() => resolve('settings'));
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
