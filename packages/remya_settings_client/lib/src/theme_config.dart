import 'dart:convert';

import 'package:toml/toml.dart';

/// Versioned public configuration. Keep Flutter and system backends out of here.
class ThemeConfig {
  const ThemeConfig({this.styleVariant = 'tonal_spot', this.mode = 'light'});

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

  String toJson() => jsonEncode(toMap());
}
