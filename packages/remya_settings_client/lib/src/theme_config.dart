import 'dart:convert';

import 'package:toml/toml.dart';

const materialThemeModeSettingId = 'themes.material-theme-mode';

/// Versioned public configuration. Keep Flutter and system backends out of here.
class ThemeConfig {
  const ThemeConfig({
    this.styleVariant = 'tonal_spot',
    this.mode = 'light',
    this.seedColor,
  });

  /// The Material seed when no accent has been chosen.
  static const defaultSeedColor = '#8054C9';

  static const styles = {
    'tonal_spot',
    'fidelity',
    'monochrome',
    'neutral',
    'vibrant',
    'expressive',
    'content',
    'rainbow',
    'fruit_salad',
  };
  final String styleVariant;
  final String mode;

  /// `#RRGGBB`, published separately by the `accent` key so `theme` stays version 1.
  final String? seedColor;

  /// Reads the `accent` D-Bus value or the content of `accent.toml`.
  static String? seedFromAccent(Map<String, dynamic> accent) {
    final color = accent['color'];
    return color is String && RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(color)
        ? color
        : null;
  }

  static String? seedFromAccentFile(String content) =>
      seedFromAccent(TomlDocument.parse(content).toMap());

  ThemeConfig withSeed(String? seed) =>
      .new(styleVariant: styleVariant, mode: mode, seedColor: seed);

  factory ThemeConfig.parse(String content) {
    if (content.trim().isEmpty) {
      throw const FormatException('Theme configuration is empty');
    }
    return .fromMap(TomlDocument.parse(content).toMap());
  }

  factory ThemeConfig.fromMap(Map<String, dynamic> map) {
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
    final style = theme['style_variant'] ?? 'tonal_spot';
    final stored = theme['theme_mode'];
    final mode = stored == 'system' ? 'light' : stored ?? 'light';
    if (!styles.contains(style) || !const {'light', 'dark'}.contains(mode)) {
      throw const FormatException('Invalid Material style or theme mode');
    }
    return .new(styleVariant: style as String, mode: mode as String);
  }

  Map<String, dynamic> toMap() => {
    'version': 1,
    'theme': {'style_variant': styleVariant, 'theme_mode': mode},
  };

  /// Identity for change detection and for passing a theme between processes.
  String toJson() => jsonEncode({...toMap(), 'seed_color': ?seedColor});
}
