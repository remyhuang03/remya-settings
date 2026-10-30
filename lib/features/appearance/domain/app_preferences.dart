import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';
export 'package:remya_settings_client/remya_settings_client.dart'
    show MaterialStyleKey;

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
  ).theme(brightness);

  @override
  bool operator ==(Object other) =>
      other is AppPreferences &&
      styleVariant == other.styleVariant &&
      themeMode == other.themeMode;

  @override
  int get hashCode => Object.hash(styleVariant, themeMode);
}
