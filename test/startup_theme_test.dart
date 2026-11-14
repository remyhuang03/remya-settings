import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/app.dart';
import 'package:remya_settings/features/appearance/domain/app_preferences.dart';
import 'package:remya_settings/features/integration/service_controllers.dart';
import 'package:remya_client/settings_contract.dart' hide AppPreferences;

void main() {
  testWidgets('the first frame uses the loaded mode, palette and accent', (
    tester,
  ) async {
    final service = _AppearanceService();
    addTearDown(service.close);
    final preferences = ServicePreferencesController(service);
    final ready = preferences.reload();
    var loaded = false;
    unawaited(ready.then((_) => loaded = true));
    await tester.pump();
    expect(loaded, isFalse);

    service.theme.complete({
      'version': 1,
      'theme': {'style_variant': 'vibrant', 'theme_mode': 'dark'},
    });
    await ready;
    expect(preferences.errorMessage, isNull);
    expect(preferences.preferences.styleVariant, DynamicSchemeVariant.vibrant);
    expect(preferences.preferences.seedColor, const Color(0xFF123456));

    // Match startup: complete the service read before mounting the application.
    await tester.pumpWidget(
      RemyaSettingsApp(preferences: preferences, client: service),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    const expected = AppPreferences(
      themeMode: .dark,
      styleVariant: .vibrant,
      seedColor: Color(0xFF123456),
    );
    expect(app.darkTheme!.colorScheme, expected.theme(.dark).colorScheme);
    final firstFrame = Theme.of(tester.element(find.byType(Scaffold).first));
    expect(firstFrame.brightness, Brightness.dark);
    expect(firstFrame.colorScheme, expected.theme(.dark).colorScheme);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _AppearanceService extends SettingsClient {
  @override
  Stream<SettingsChange> get changes => const Stream.empty();
  final theme = Completer<Map<String, dynamic>>();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async => switch (arguments.single) {
    'catalog' => {
      'version': 1,
      'sources': <Object>[],
      'coverage': {'supported': 0, 'planned': 0, 'total': 0},
      'pages': <Object>[],
      'categories': <Object>[],
    },
    'accent' => {'source': 'custom', 'color': '#123456'},
    'theme' => theme.future,
    'system' => {'mode': 'dark', 'targets': <Object>[]},
    _ => throw StateError('Unexpected service call: $method $arguments'),
  };
}
