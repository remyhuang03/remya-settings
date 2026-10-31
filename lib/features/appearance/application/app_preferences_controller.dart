import 'package:material_ui/material_ui.dart';

import '../data/app_preferences_file.dart';
import '../data/system_appearance_backend.dart';
import '../domain/app_preferences.dart';

class AppPreferencesController extends ChangeNotifier {
  AppPreferencesController({
    required this.store,
    required this.systemAppearance,
  });
  final SystemAppearanceBackend systemAppearance;
  SystemThemeState? _systemTheme;
  SystemThemeState? get systemTheme => _systemTheme;
  bool get hasConflict =>
      _systemTheme?.mode != null &&
      _systemTheme!.mode != _preferences.themeMode;
  final AppPreferencesFile store;
  AppPreferences _preferences = const .new();
  AppPreferences get preferences => _preferences;
  String? errorMessage;
  // shortcut: saves serialize per instance; add file locking for concurrent multi-instance editing.
  Future<void> _pending = Future.value();
  var _operations = 0;
  bool _disposed = false;
  bool get isBusy => _operations != 0;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _run(
    Future<void> Function() operation,
    String error, {
    bool background = false,
  }) {
    if (_disposed) return Future.value();
    if (!background) {
      _operations++;
      _notify();
    }
    final result = _pending.then((_) async {
      if (_disposed) {
        if (!background) _operations--;
        return;
      }
      try {
        await operation();
        errorMessage = null;
      } catch (failure) {
        errorMessage = '$error $failure';
      } finally {
        if (!background) _operations--;
        _notify();
      }
    });
    _pending = result;
    return result;
  }

  Future<void> retry() => reload();

  Future<void> reload() => _run(
    () async {
      final observed = await systemAppearance.read();
      if (observed.mode == null) {
        throw StateError(
          'System appearance cannot be detected; configuration was retained',
        );
      }
      var loaded = await store.load();
      if (loaded == null) {
        loaded = _preferences.copyWith(themeMode: observed.mode);
        await store.save(loaded);
      }
      if (!_disposed) {
        _systemTheme = observed;
        _preferences = loaded;
      }
    },
    'Could not reload appearance settings.',
    background: true,
  );

  Future<void> useSystemConfiguration() => _run(() async {
    final observed = await systemAppearance.read();
    if (observed.mode == null) {
      throw StateError('System appearance cannot be detected');
    }
    final current = await store.load() ?? _preferences;
    final next = current.copyWith(themeMode: observed.mode);
    await store.save(next);
    if (!_disposed) {
      _systemTheme = observed;
      _preferences = next;
    }
  }, 'Could not adopt system appearance.');

  Future<void> setStyleVariant(DynamicSchemeVariant value) => _run(() async {
    final current = await store.load() ?? _preferences;
    final observed = await systemAppearance.read();
    final next = current.copyWith(styleVariant: value);
    await store.save(next);
    if (!_disposed) {
      _preferences = next;
      _systemTheme = observed;
    }
  }, 'Could not save the Material palette.');

  Future<void> setThemeMode(SystemThemeMode value) => _run(() async {
    final current = await store.load() ?? _preferences;
    final next = current.copyWith(themeMode: value);
    await store.save(next);
    try {
      final applied = await systemAppearance.apply(value);
      if (applied.mode != value) {
        throw StateError(
          'System appearance readback does not match the request',
        );
      }
      if (!_disposed) {
        _preferences = next;
        _systemTheme = applied;
      }
    } catch (error) {
      try {
        await store.save(current);
      } catch (restoreError) {
        throw StateError(
          '$error; app configuration could not be restored: $restoreError',
        );
      }
      // Reflect any incomplete system rollback without hiding its original error.
      try {
        final observed = await systemAppearance.read();
        if (!_disposed) {
          _systemTheme = observed;
          _preferences = current;
        }
      } catch (_) {}
      rethrow;
    }
  }, 'Could not apply system appearance.');

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppPreferencesScope extends InheritedNotifier<AppPreferencesController> {
  const AppPreferencesScope({
    super.key,
    required AppPreferencesController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppPreferencesController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppPreferencesScope>()!
      .notifier!;
}
