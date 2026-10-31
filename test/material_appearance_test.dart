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
  test(
    'Material catalog choices and default match the app preferences',
    () async {
      final catalog = await SettingsCatalog.load();
      final controls = catalog.page('themes').controls;
      expect(
        controls
            .firstWhere((setting) => setting.id == materialStyleSettingId)
            .value,
        const AppPreferences().styleVariant.label,
      );
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
    },
  );

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
      await tester.ensureVisible(find.byKey(const ValueKey('nav-page-themes')));
      await tester.tap(find.byKey(const ValueKey('nav-page-themes')));
      await tester.pumpAndSettle();
      final light = find.byKey(
        const ValueKey('$materialThemeModeSettingId-Light'),
      );
      final dark = find.byKey(
        const ValueKey('$materialThemeModeSettingId-Dark'),
      );
      expect(find.text('Material Design'), findsOneWidget);
      expect(find.text('Appearance preferences'), findsNothing);
      expect(find.text('Reload settings'), findsNothing);
      expect(
        find.byKey(ValueKey('control-$materialStyleSettingId')),
        findsOneWidget,
      );
      expect(tester.widget<IconButton>(light).isSelected, isTrue);
      expect(tester.widget<IconButton>(dark).isSelected, isFalse);
      expect(find.text('Follow system'), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(SettingsShell))).brightness,
        Brightness.light,
      );

      Future<void> select(String id, String value) async {
        final choice = tester.widget<DropdownButtonFormField<String>>(
          find.byKey(ValueKey('control-$id')),
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
      await select(materialStyleSettingId, 'Monochrome');
      await tester.runAsync(() async {
        await tester.ensureVisible(dark);
        await tester.tap(dark);
        while (controller.isBusy) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();
      expect(system.applyCalls, 1);
      expect(tester.widget<IconButton>(light).isSelected, isFalse);
      expect(tester.widget<IconButton>(dark).isSelected, isTrue);
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
        await tester.ensureVisible(light);
        await tester.tap(light);
        while (controller.isBusy) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(system.applyCalls, 2);
        expect(
          await store.load(),
          const AppPreferences(styleVariant: .monochrome, themeMode: .light),
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
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const ValueKey('control-$materialStyleSettingId')),
            )
            .initialValue,
        'Vibrant',
      );
      expect(tester.widget<IconButton>(light).isSelected, isTrue);
      await tester.runAsync(() async {
        store.file.writeAsStringSync('version = 2');
        await controller.reload();
      });
      await tester.pumpAndSettle();
      expect(find.text('Unable to update settings'), findsOneWidget);
      await tester.tap(find.text('Details'));
      await tester.pumpAndSettle();
      expect(find.textContaining(store.file.path), findsOneWidget);
      await tester.tap(find.text('Close').last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.light,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
