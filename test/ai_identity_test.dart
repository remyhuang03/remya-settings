import 'dart:convert';
import 'dart:io';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remya_ui/ai_identity.dart';

void main() {
  setUpAll(loadAiIdentity);

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
