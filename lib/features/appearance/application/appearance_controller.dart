import 'package:flutter/foundation.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_ui/remya_ui.dart';

/// The Settings app's shared theme and the independently managed system mode.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this._client)
    : _theme = SettingsThemeController.service(client: _client) {
    _theme.addListener(notifyListeners);
  }

  final SettingsClient _client;
  final SettingsThemeController _theme;
  RemyaTheme get theme => _theme.theme;

  String? savedSystemMode;
  String? systemMode;
  bool hasConflict = false;
  bool isBusy = false;
  bool _loaded = false;
  String? _readError;
  String? _actionError;
  (String, List<String>)? _failedAction;
  int _request = 0;
  bool _disposed = false;

  bool get canApplyToSystem => _loaded && !isBusy;
  String? get errorMessage => _actionError ?? _readError ?? _theme.error;

  Future<void> start() async {
    await Future.wait([_theme.start(), reload()]);
  }

  Future<void> reload() async {
    if (_disposed) return;
    final request = ++_request;
    try {
      final state = await _client.call('Get', ['appearance']);
      if (request == _request) apply(state);
    } catch (error) {
      if (_disposed || request != _request || _readError == '$error') return;
      _readError = '$error';
      notifyListeners();
    }
  }

  void apply(Map<String, dynamic> state) {
    if (_disposed) return;
    _request++;
    final saved = state['saved'] as String?;
    final system = state['system'] as String?;
    final conflict = state['conflict'] == true;
    final error = state['error'] as String?;
    if (_loaded &&
        savedSystemMode == saved &&
        systemMode == system &&
        hasConflict == conflict &&
        _readError == error) {
      return;
    }
    _loaded = true;
    savedSystemMode = saved;
    systemMode = system;
    hasConflict = conflict;
    _readError = error;
    notifyListeners();
  }

  Future<void> useSystemConfiguration() =>
      _execute('Resolve', ['appearance', 'system']);

  Future<void> applySavedConfiguration() =>
      _execute('Resolve', ['appearance', 'settings']);

  Future<void> applyToSystem() =>
      _execute('Set', [applyThemeToSystemSettingId, 'apply']);

  Future<void> retry() async {
    if (isBusy) return;
    if (_failedAction case (final method, final args)?) {
      await _execute(method, args);
    } else {
      await Future.wait([_theme.reload(), reload()]);
    }
  }

  Future<void> _execute(String method, List<String> args) async {
    if (_disposed || isBusy) return;
    isBusy = true;
    notifyListeners();
    try {
      await _client.call(method, args);
      _failedAction = null;
      _actionError = null;
      await reload();
    } catch (error) {
      _failedAction = (method, args);
      _actionError = '$error';
    } finally {
      isBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _theme.dispose();
    super.dispose();
  }
}
