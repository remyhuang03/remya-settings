import 'dart:convert';
import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/ai_identity.dart';

double _hueDistance(Color a, Color b) {
  final d = (Hct.fromInt(a.toARGB32()).hue - Hct.fromInt(b.toARGB32()).hue)
      .abs();
  return d > 180 ? 360 - d : d;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAiIdentity);

  final light = ColorScheme.fromSeed(seedColor: const Color(0xFF3060E0));
  final dark = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3060E0),
    brightness: .dark,
  );

  test('gray or unknown brands fall back to scheme colors', () {
    expect(aiProviderBrandColor('openai'), isNull);
    for (final scheme in [light, dark]) {
      final tone = scheme.brightness == .dark ? 80.0 : 40.0;
      final fallbacks = [scheme.primary, scheme.tertiary, scheme.secondary];
      for (final (index, id) in ['openai', 'unknown', 'cursor'].indexed) {
        final accent = aiProviderAccent(id, scheme, index: index);
        final hct = Hct.fromInt(accent.toARGB32());
        expect(hct.tone, closeTo(tone, 1));
        expect(_hueDistance(accent, fallbacks[index]), lessThan(2), reason: id);
      }
    }
  });

  test('saturated brands harmonize toward primary and stay distinct', () {
    final brand = aiProviderBrandColor('claude')!;
    for (final scheme in [light, dark]) {
      final accent = aiProviderAccent('claude', scheme);
      final before = _hueDistance(brand, scheme.primary);
      final after = _hueDistance(accent, scheme.primary);
      expect(after, lessThan(before));
      expect(after, greaterThan(30));
      expect(
        Hct.fromInt(accent.toARGB32()).tone,
        closeTo(scheme.brightness == .dark ? 80 : 40, 1),
      );
    }
  });

  testWidgets('every manifest icon exists and parses', (tester) async {
    const dir = '../remya-core/packages/remya_ui/assets/ai_providers';
    final manifest = jsonDecode(
      File('$dir/manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(manifest, isNotEmpty);
    await tester.runAsync(() async {
      for (final id in manifest.keys) {
        final path = aiProviderIcon(id)!;
        expect(File('$dir/${manifest[id]['icon']}').existsSync(), isTrue);
        final info = await vg.loadPicture(SvgAssetLoader(path), null);
        expect(info.size.isEmpty, isFalse, reason: id);
        info.picture.dispose();
      }
    });
  });
}
