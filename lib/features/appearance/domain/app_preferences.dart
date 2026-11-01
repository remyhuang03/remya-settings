import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';
export 'package:remya_settings_client/remya_settings_client.dart'
    show MaterialStyleKey;

import '../../../src/rust/appearance_bridge/api.dart';
export '../../../src/rust/appearance_bridge/api.dart' show SystemThemeMode;

const materialStyleSettingId = 'themes.material-style-variant';
const materialThemeModeSettingId = 'themes.material-theme-mode';
const accentSourceSettingId = 'colors.8983f367';
const accentColorSettingId = 'colors.6f67371e';

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
    this.styleVariant = .tonalSpot,
    this.themeMode = .light,
    this.seedColor = RemyaTheme.defaultSeed,
  });

  final DynamicSchemeVariant styleVariant;
  final SystemThemeMode themeMode;

  /// Owned by the accent setting, so it is not part of the theme file's [toMap].
  final Color seedColor;

  AppPreferences copyWith({
    DynamicSchemeVariant? styleVariant,
    SystemThemeMode? themeMode,
    Color? seedColor,
  }) => .new(
    styleVariant: styleVariant ?? this.styleVariant,
    themeMode: themeMode ?? this.themeMode,
    seedColor: seedColor ?? this.seedColor,
  );

  factory AppPreferences.fromMap(Map<String, dynamic> map) {
    final theme = RemyaTheme.fromMap(map);
    return .new(
      styleVariant: theme.styleVariant,
      themeMode: theme.mode == .dark ? .dark : .light,
    );
  }

  Map<String, dynamic> toMap() => {
    'version': 1,
    'theme': {
      'style_variant': styleVariant.configKey,
      'theme_mode': themeMode.name,
    },
  };

  ThemeData theme(Brightness brightness) => RemyaTheme(
    styleVariant: styleVariant,
    mode: themeMode.materialMode,
    seedColor: seedColor,
  ).theme(brightness);

  @override
  bool operator ==(Object other) =>
      other is AppPreferences &&
      styleVariant == other.styleVariant &&
      themeMode == other.themeMode &&
      seedColor == other.seedColor;

  @override
  int get hashCode => Object.hash(styleVariant, themeMode, seedColor);
}
