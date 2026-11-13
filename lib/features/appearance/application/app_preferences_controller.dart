import 'package:material_ui/material_ui.dart';

import '../data/system_appearance_backend.dart';
import '../domain/app_preferences.dart';

abstract class AppPreferencesController extends ChangeNotifier {
  AppPreferences get preferences;
  SystemThemeState? get systemTheme;
  bool get hasConflict;
  bool get isBusy;
  String? errorMessage;
  String get accentSource;
  String? get accentError;
  Future<void> reload();
  Future<void> retry();
  Future<void> useSystemConfiguration();
  Future<void> setStyleVariant(DynamicSchemeVariant value);
  Future<void> setThemeMode(SystemThemeMode value);
  Future<void> setAccentSource(String source);
  Future<void> setAccentColor(String hex);
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
