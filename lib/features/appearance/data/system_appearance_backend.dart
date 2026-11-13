enum SystemThemeMode { light, dark }

enum ThemeTargetStatus { detected, applied, unchanged, unavailable }

class SystemThemeState {
  const SystemThemeState({this.mode, required this.targets});
  final SystemThemeMode? mode;
  final List<ThemeTargetResult> targets;
}

class ThemeTargetResult {
  const ThemeTargetResult({
    required this.name,
    required this.status,
    required this.detail,
  });
  final String name;
  final ThemeTargetStatus status;
  final String detail;
}

abstract interface class SystemAppearanceBackend {
  Future<SystemThemeState> read();
  Future<SystemThemeState> apply(SystemThemeMode mode);
}
