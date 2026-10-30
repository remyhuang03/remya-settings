import 'package:material_ui/material_ui.dart';

import 'theme_config.dart';

extension MaterialStyleKey on DynamicSchemeVariant {
  String get configKey => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => '_${match[0]!.toLowerCase()}',
  );
}

/// Shared with the settings writer. The bar only reads this configuration.
class RemyaTheme {
  const RemyaTheme({this.styleVariant = .tonalSpot, this.mode = .light});

  final DynamicSchemeVariant styleVariant;
  final ThemeMode mode;

  factory RemyaTheme.parse(String content) =>
      .fromConfig(ThemeConfig.parse(content));

  factory RemyaTheme.fromMap(Map<String, dynamic> map) =>
      .fromConfig(ThemeConfig.fromMap(map));

  factory RemyaTheme.fromConfig(ThemeConfig config) => .new(
    styleVariant: DynamicSchemeVariant.values.singleWhere(
      (value) => value.configKey == config.styleVariant,
    ),
    mode: config.mode == 'dark' ? .dark : .light,
  );

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
}
