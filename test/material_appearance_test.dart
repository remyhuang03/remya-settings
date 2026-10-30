import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/app.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/appearance/data/app_preferences_file.dart';
import 'package:remya_settings/features/appearance/domain/app_preferences.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';

import 'support/fake_system_appearance.dart';

void main() {
  test('Material catalog choices match the implemented enums', () async {
    final catalog = await SettingsCatalog.load();
    final controls = catalog.page('themes').controls;
    expect(
      controls
          .firstWhere((setting) => setting.id == materialStyleSettingId)
          .options,
      DynamicSchemeVariant.values.map((value) => value.label).toList(),
    );
    expect(
      controls
          .firstWhere((setting) => setting.id == materialThemeModeSettingId)
          .options,
      SystemThemeMode.values.map((value) => value.label).toList(),
    );
  });

  testWidgets(
    'Themes controls update the whole app and persist without losing navigation',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'remya-material-ui-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = AppPreferencesFile(File('${directory.path}/config.toml'));
      final system = FakeSystemAppearance();
      final controller = AppPreferencesController(
        store: store,
        systemAppearance: system,
      );
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 1000);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.runAsync(() async {
        await controller.reload();
        await tester.pumpWidget(RemyaSettingsApp(preferences: controller));
        await SettingsCatalog.load();
      });
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-personalization')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-page-themes')));
      await tester.pumpAndSettle();
      expect(find.text('Material Design'), findsOneWidget);
      expect(find.text('Follow system'), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SettingsShell))).brightness,
        Brightness.light,
      );

      Future<void> select(String id, String old, String value) async {
        final choice = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(ValueKey('$id-$old')),
        );
        expect(choice.onChanged, isNotNull);
        await tester.runAsync(() async {
          choice.onChanged!(value);
          while (controller.isBusy) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
        });
        await tester.pumpAndSettle();
      }

      final oldColor = tester
          .widget<MaterialApp>(find.byType(MaterialApp))
          .theme!
          .colorScheme
          .primary;
      await select(materialStyleSettingId, 'Tonal spot', 'Monochrome');
      await select(materialThemeModeSettingId, 'Light', 'Dark');
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.themeMode, ThemeMode.dark);
      expect(app.darkTheme!.brightness, Brightness.dark);
      expect(app.theme!.colorScheme.primary, isNot(oldColor));
      expect(
        Theme.of(tester.element(find.byType(SettingsShell))).brightness,
        Brightness.dark,
      );
      expect(find.text('Themes'), findsWidgets);
      expect(find.byKey(const ValueKey('nav-page-themes')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        expect(
          await store.load(),
          const AppPreferences(styleVariant: .monochrome, themeMode: .dark),
        );
        store.file.writeAsStringSync(
          'version = 1\n[theme]\ntheme_mode = "light"\nstyle_variant = "vibrant"\n',
        );
        system.mode = .light;
        await controller.reload();
      });
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(
        find.byKey(ValueKey('$materialStyleSettingId-Vibrant')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('$materialThemeModeSettingId-Light')),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        store.file.writeAsStringSync('version = 2');
        await controller.reload();
      });
      await tester.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsOneWidget);
      expect(find.text(store.file.path), findsOneWidget);
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
