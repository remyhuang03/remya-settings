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
  const RemyaTheme({
    this.styleVariant = .tonalSpot,
    this.mode = .light,
    this.seedColor = defaultSeed,
  });

  static const defaultSeed = Color(0xFF8054C9);

  /// Parses `#RRGGBB`; anything else keeps the default seed.
  static Color seedFromHex(String? hex) {
    final value = hex == null
        ? null
        : int.tryParse(hex.substring(1), radix: 16);
    return value == null ? defaultSeed : Color(0xFF000000 | value);
  }

  final DynamicSchemeVariant styleVariant;
  final ThemeMode mode;
  final Color seedColor;

  factory RemyaTheme.parse(String content) =>
      .fromConfig(ThemeConfig.parse(content));

  factory RemyaTheme.fromMap(Map<String, dynamic> map) =>
      .fromConfig(ThemeConfig.fromMap(map));

  factory RemyaTheme.fromConfig(ThemeConfig config) => .new(
    styleVariant: DynamicSchemeVariant.values.singleWhere(
      (value) => value.configKey == config.styleVariant,
    ),
    mode: config.mode == 'dark' ? .dark : .light,
    seedColor: seedFromHex(config.seedColor),
  );

  ThemeData theme(Brightness brightness) => .new(
    useMaterial3: true,
    colorScheme: .fromSeed(
      seedColor: seedColor,
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
