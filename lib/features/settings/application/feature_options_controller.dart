import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

/// State of one service feature with saved options, a system readback and
/// conflicts: the Hyprland option groups `input` (Mouse, Touchpad, Keyboard
/// shortcuts) and `desktop` (Multitasking, Cursor, Background, Power), and the
/// cursor and icon theme packs (`themes`).
class FeatureOptionsController extends ChangeNotifier {
  FeatureOptionsController(this.client, {this.feature = 'input'}) {
    _changes = client.changes.listen((change) {
      if (_disposed || change.topic != feature) return;
      if (isBusy || _reading != null) {
        unawaited(_refresh());
      } else {
        _apply(change.value);
      }
    }, onError: (Object error) => debugPrint('$feature changes: $error'));
  }
  final SettingsClient client;
  final String feature;
  StreamSubscription<SettingsChange>? _changes;
  Map<String, dynamic> state = {};
  String? _readError;
  String? _writeError;
  Completer<void>? _writing;
  Future<void>? _reading;
  bool _dirty = false;
  bool _readFailed = false;
  bool _disposed = false;

  String? get errorMessage => _writeError ?? _readError;
  bool get isBusy => _writing != null;

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
    _readError = state['error'] as String?;
    _readFailed = false;
    notifyListeners();
  }

  Future<void> reload() {
    _writeError = null;
    return _refresh();
  }

  Future<void> _refresh() {
    if (_disposed) return Future<void>.value();
    _dirty = true;
    return _reading ??= _readChanges();
  }

  Future<void> _readChanges() async {
    // Register the in-flight future even if a test client fails synchronously.
    await Future<void>.value();
    try {
      while (_dirty && !_disposed) {
        while (_writing != null) {
          await _writing!.future;
        }
        if (_disposed) return;
        _dirty = false;
        try {
          final next = await client.call('Get', [feature]);
          if (!_dirty && !_disposed) _apply(next);
        } catch (error) {
          if (_dirty || _disposed) continue;
          _readFailed = true;
          _readError = '$error';
          notifyListeners();
        }
      }
    } finally {
      _reading = null;
    }
  }

  /// Runs one write; a rejected write stays visible until the next change.
  Future<bool> _change(Future<Map<String, dynamic>> Function() action) async {
    if (_disposed || isBusy) return false;
    final write = _writing = Completer<void>();
    if (_reading != null) _dirty = true;
    _writeError = null;
    notifyListeners();
    var succeeded = false;
    try {
      final next = await action();
      if (!_disposed) _apply(next);
      succeeded = true;
    } catch (error) {
      if (!_disposed) _writeError = '$error';
    } finally {
      _writing = null;
      write.complete();
      if (!_disposed) notifyListeners();
    }
    if (!succeeded) await _refresh();
    return succeeded;
  }

  Future<bool> set(String id, Object value) =>
      _change(() => client.call('Set', [id, jsonEncode(value)]));
  Future<bool> resolve(String source) =>
      _change(() => client.call('Resolve', [feature, source]));

  @override
  void dispose() {
    _disposed = true;
    unawaited(_changes?.cancel());
    super.dispose();
  }
}
