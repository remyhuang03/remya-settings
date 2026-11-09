import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

/// State of one service feature with saved options, a system readback and
/// conflicts: the Hyprland option groups `input` (Mouse, Touchpad, Keyboard
/// shortcuts) and `desktop` (Multitasking, Cursor, Background, Power), and the
/// cursor and icon theme packs (`themes`).
class FeatureOptionsController extends ChangeNotifier {
  FeatureOptionsController(this.client, {this.feature = 'input'}) {
    _changes = client.changes.listen((change) {
      if (change.topic == feature && !isBusy) _apply(change.value);
    }, onError: (Object error) => debugPrint('$feature changes: $error'));
  }
  final SettingsClient client;
  final String feature;
  StreamSubscription<SettingsChange>? _changes;
  Map<String, dynamic> state = {};
  String? errorMessage;
  bool isBusy = false;
  bool _readFailed = false;

  bool get isLoaded => state.isNotEmpty;
  Map<String, dynamic> get options =>
      (state['options'] as Map?)?.cast<String, dynamic>() ?? {};
  Object? option(String id) => options[id];
  bool get hasConflict => state['conflict'] == true;
  String? get writeBlocked => state['write_blocked'] as String?;
  bool get canChange =>
      isLoaded &&
      !_readFailed &&
      !hasConflict &&
      writeBlocked == null &&
      !isBusy;
  List<Map<String, dynamic>> list(String key) => (state[key] as List? ?? [])
      .cast<Map>()
      .map((m) => m.cast<String, dynamic>())
      .toList();
  List<String> names(String key) => (state[key] as List? ?? []).cast<String>();

  void _apply(Object? next) {
    if (next is! Map) return;
    state = next.cast<String, dynamic>();
    errorMessage = state['error'] as String?;
    _readFailed = false;
    notifyListeners();
  }

  Future<void> reload() async {
    try {
      _apply(await client.call('Get', [feature]));
    } catch (error) {
      _readFailed = true;
      errorMessage = '$error';
      notifyListeners();
    }
  }

  /// Runs one write; a rejected write stays visible until the next change.
  Future<bool> _change(Future<Map<String, dynamic>> Function() action) async {
    if (isBusy) return false;
    isBusy = true;
    notifyListeners();
    String? failure;
    try {
      _apply(await action());
    } catch (error) {
      failure = '$error';
      await reload();
    }
    errorMessage = failure ?? errorMessage;
    isBusy = false;
    notifyListeners();
    return failure == null;
  }

  Future<bool> set(String id, Object value) =>
      _change(() => client.call('Set', [id, jsonEncode(value)]));
  Future<bool> resolve(String source) =>
      _change(() => client.call('Resolve', [feature, source]));

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
