/// AI provider brand icons and colors shared by Remya applications.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

const _root = 'packages/remya_settings_client/assets';

Map<String, ({String icon, Color? color})> _providers = const {};
Future<void>? _loading;

/// Loads the provider manifest and registers the icon license once.
Future<void> loadAiIdentity() => _loading ??= _load();

Future<void> _load() async {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'AI provider icons: Lobe Icons',
    ], await rootBundle.loadString('$_root/licenses/lobe-icons.txt'));
  });
  final manifest = jsonDecode(
    await rootBundle.loadString('$_root/ai_providers/manifest.json'),
  ) as Map<String, dynamic>;
  _providers = {
    for (final MapEntry(:key, :value) in manifest.entries)
      key: (
        icon: '$_root/ai_providers/${value['icon']}',
        color: switch (value['color']) {
          final String hex => Color(
            0xFF000000 | int.parse(hex.substring(1), radix: 16),
          ),
          _ => null,
        },
      ),
  };
}

/// Asset key for `SvgPicture.asset`, or null for an unknown provider.
String? aiProviderIcon(String id) => _providers[id]?.icon;

Color? aiProviderBrandColor(String id) => _providers[id]?.color;

/// The brand color harmonized toward [ColorScheme.primary] at a readable
/// tone; gray or unknown brands use a scheme color picked by [index].
Color aiProviderAccent(String id, ColorScheme scheme, {int index = 0}) {
  final brand = aiProviderBrandColor(id);
  final source = brand == null || Hct.fromInt(brand.toARGB32()).chroma < 16
      ? [scheme.primary, scheme.tertiary, scheme.secondary][index % 3]
      : Color(Blend.harmonize(brand.toARGB32(), scheme.primary.toARGB32()));
  final hct = Hct.fromInt(source.toARGB32())
    ..tone = scheme.brightness == .dark ? 80 : 40;
  return Color(hct.toInt());
}
