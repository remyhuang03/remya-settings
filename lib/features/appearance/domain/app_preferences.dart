import 'package:material_ui/material_ui.dart';

import '../../../src/rust/appearance_bridge/api.dart';
export '../../../src/rust/appearance_bridge/api.dart' show SystemThemeMode;

const materialStyleSettingId = 'themes.material-style-variant';
const materialThemeModeSettingId = 'themes.material-theme-mode';

extension MaterialStyleLabel on DynamicSchemeVariant {
  String get label => switch (this) {
    .tonalSpot => 'Tonal spot',
    .fidelity => 'Fidelity',
    .monochrome => 'Monochrome',
    .neutral => 'Neutral',
    .vibrant => 'Vibrant',
    .expressive => 'Expressive',
    .content => 'Content',
    .rainbow => 'Rainbow',
    .fruitSalad => 'Fruit salad',
  };

  String get configKey => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => '_${match[0]!.toLowerCase()}',
  );
}

extension AppThemeModeLabel on SystemThemeMode {
  String get label => switch (this) {
    .light => 'Light',
    .dark => 'Dark',
  };

  ThemeMode get materialMode => switch (this) {
    .light => .light,
    .dark => .dark,
  };
}

class AppPreferences {
  const AppPreferences({
    this.styleVariant = .expressive,
    this.themeMode = .light,
  });

  final DynamicSchemeVariant styleVariant;
  final SystemThemeMode themeMode;

  AppPreferences copyWith({
    DynamicSchemeVariant? styleVariant,
    SystemThemeMode? themeMode,
  }) => .new(
    styleVariant: styleVariant ?? this.styleVariant,
    themeMode: themeMode ?? this.themeMode,
  );

  factory AppPreferences.fromMap(Map<String, dynamic> map) {
    if (map['version'] is! int ||
        map['version'] != 1 ||
        map.keys.any((key) => !const {'version', 'theme'}.contains(key))) {
      throw const FormatException('Unsupported app preferences schema');
    }
    final theme = map['theme'] ?? <String, dynamic>{};
    if (theme is! Map ||
        theme.keys.any(
          (key) => !const {'style_variant', 'theme_mode'}.contains(key),
        )) {
      throw const FormatException('Invalid theme table');
    }
    final styleKey = theme['style_variant'] ?? 'expressive';
    final storedMode = theme['theme_mode'];
    final modeKey = storedMode == 'system' ? 'light' : storedMode ?? 'light';
    final styles = DynamicSchemeVariant.values.where(
      (value) => value.configKey == styleKey,
    );
    final modes = SystemThemeMode.values.where(
      (value) => value.name == modeKey,
    );
    if (styles.isEmpty || modes.isEmpty) {
      throw const FormatException('Invalid Material style or theme mode');
    }
    return .new(styleVariant: styles.single, themeMode: modes.single);
  }

  Map<String, dynamic> toMap() => {
    'version': 1,
    'theme': {
      'style_variant': styleVariant.configKey,
      'theme_mode': themeMode.name,
    },
  };

  ThemeData theme(Brightness brightness) => .new(
    useMaterial3: true,
    colorScheme: .fromSeed(
      seedColor: const Color(0xFF8054C9),
      brightness: brightness,
      dynamicSchemeVariant: styleVariant,
    ),
    iconButtonTheme: const .new(variant: .material3Expressive),
    fontFamilyFallback: const [
      'Noto Sans CJK SC',
      'Noto Sans CJK TC',
      'sans-serif',
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is AppPreferences &&
      styleVariant == other.styleVariant &&
      themeMode == other.themeMode;

  @override
  int get hashCode => Object.hash(styleVariant, themeMode);
}
