import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/app.dart';
import 'package:remya_settings/features/appearance/application/appearance_controller.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_ui/remya_ui.dart';

void main() {
  testWidgets(
    'the first frame uses the loaded mode, palette, accent and contrast',
    (tester) async {
      final service = _AppearanceService();
      addTearDown(service.close);
      final appearance = AppearanceController(service);
      final ready = appearance.start();
      var loaded = false;
      unawaited(ready.then((_) => loaded = true));
      await tester.pump();
      expect(loaded, isFalse);

      service.theme.complete({
        'version': 1,
        'theme': {
          'style_variant': 'vibrant',
          'theme_mode': 'dark',
          'contrast': 'high',
        },
      });
      await ready;
      expect(appearance.errorMessage, isNull);
      expect(appearance.theme.styleVariant, DynamicSchemeVariant.vibrant);
      expect(appearance.theme.seedColor, const Color(0xFF123456));

      // Match startup: complete the service read before mounting the application.
      await tester.pumpWidget(
        RemyaSettingsApp(appearance: appearance, client: service),
      );
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      const expected = RemyaTheme(
        mode: .dark,
        contrast: .high,
        styleVariant: .vibrant,
        seedColor: Color(0xFF123456),
      );
      expect(app.darkTheme!.colorScheme, expected.theme(.dark).colorScheme);
      final firstFrame = Theme.of(tester.element(find.byType(Scaffold).first));
      expect(firstFrame.brightness, Brightness.dark);
      expect(firstFrame.colorScheme, expected.theme(.dark).colorScheme);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'system apply is explicit and a failed apply survives a refresh',
    () async {
      final service = _AppearanceService();
      addTearDown(service.close);
      final appearance = AppearanceController(service);
      addTearDown(appearance.dispose);
      service.theme.complete(const ThemeConfig(mode: 'dark').toMap());

      await appearance.start();
      expect(appearance.theme.mode, ThemeMode.dark);
      expect(appearance.systemMode, 'light');
      expect(appearance.hasConflict, isFalse);
      expect(service.executed, isEmpty);

      service.failAction = true;
      await appearance.applyToSystem();
      await appearance.reload();
      expect(appearance.errorMessage, contains('System theme write failed'));
      expect(appearance.systemMode, 'light');

      service.failAction = false;
      await appearance.retry();
      expect(service.executed, [
        ['Set', applyThemeToSystemSettingId, 'apply'],
        ['Set', applyThemeToSystemSettingId, 'apply'],
      ]);
      expect(appearance.errorMessage, isNull);
      expect(appearance.systemMode, 'dark');
      expect(appearance.savedSystemMode, 'dark');
      expect(appearance.theme.mode, ThemeMode.dark);
    },
  );
}

class _AppearanceService extends SettingsClient {
  @override
  Stream<SettingsChange> get changes => const Stream.empty();
  final theme = Completer<Map<String, dynamic>>();
  final executed = <List<String>>[];
  bool failAction = false;
  var system = <String, dynamic>{
    'saved': null,
    'system': 'light',
    'conflict': false,
  };

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Set' && arguments.first == applyThemeToSystemSettingId) {
      executed.add([method, ...arguments]);
      if (failAction) throw StateError('System theme write failed');
      system = {'saved': 'dark', 'system': 'dark', 'conflict': false};
      return system;
    }
    return switch (arguments.single) {
      'catalog' => {
        'version': 1,
        'sources': <Object>[],
        'coverage': {'supported': 0, 'planned': 0, 'total': 0},
        'pages': <Object>[],
        'categories': <Object>[],
      },
      'accent' => {'source': 'custom', 'color': '#123456'},
      'theme' => theme.future,
      'appearance' => system,
      _ => throw StateError('Unexpected service call: $method $arguments'),
    };
  }
}
