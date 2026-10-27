import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/appearance/data/app_preferences_file.dart';
import 'package:remya_settings/features/appearance/domain/app_preferences.dart';

import 'support/fake_system_appearance.dart';

void main() {
  late Directory directory;
  late File file;
  late AppPreferencesFile store;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('remya-preferences-');
    file = File('${directory.path}/config.toml');
    store = AppPreferencesFile(file);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'every style and theme mode round-trips without seed configuration',
    () async {
      for (final style in DynamicSchemeVariant.values) {
        for (final mode in SystemThemeMode.values) {
          final preferences = AppPreferences(
            styleVariant: style,
            themeMode: mode,
          );
          await store.save(preferences);
          expect(await store.load(), preferences);
          expect(preferences.theme(.light).brightness, Brightness.light);
          expect(preferences.theme(.dark).brightness, Brightness.dark);
          expect(
            (preferences.toMap()['theme'] as Map).keys,
            unorderedEquals(['style_variant', 'theme_mode']),
          );
        }
      }
      expect(file.statSync().mode & 0x1ff, 0x180);
    },
  );

  test('debug and release paths use this app identity and XDG rules', () {
    expect(
      AppPreferencesFile.resolve(
        isDebug: true,
        workingDirectory: directory,
      ).path,
      '${directory.path}/config/config.local.toml',
    );
    expect(
      AppPreferencesFile.resolve(
        isDebug: false,
        environment: {'XDG_CONFIG_HOME': '/config', 'HOME': '/home/example'},
      ).path,
      '/config/remya/settings/config.toml',
    );
    expect(
      AppPreferencesFile.resolve(
        isDebug: false,
        environment: {'XDG_CONFIG_HOME': 'relative', 'HOME': '/home/example'},
      ).path,
      '/home/example/.config/remya/settings/config.toml',
    );
    expect(
      () => AppPreferencesFile.resolve(isDebug: false, environment: {}),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'missing files differ from empty, malformed and unsupported configs',
    () async {
      expect(await store.load(), isNull);
      for (final invalid in [
        '',
        '[theme',
        'version = 2',
        'version = 1.0',
        'version = 1\nother = true',
        'version = 1\ntheme = "dark"',
        'version = 1\n[theme]\ntheme_mode = false',
        'version = 1\n[theme]\nstyle_variant = "unknown"',
        'version = 1\n[theme]\nseed_color = "#ffffff"',
      ]) {
        file.writeAsStringSync(invalid);
        await expectLater(store.load(), throwsA(isA<Exception>()));
        expect(file.readAsStringSync(), invalid);
      }
      file.writeAsStringSync('version = 1\n');
      expect(await store.load(), const AppPreferences());
    },
  );

  test('atomic save retains symbolic links and existing permissions', () async {
    await store.save(const AppPreferences());
    expect((await Process.run('chmod', ['640', '--', file.path])).exitCode, 0);
    final link = Link('${directory.path}/linked.toml')..createSync(file.path);
    final linked = AppPreferencesFile(File(link.path));
    const next = AppPreferences(themeMode: .dark, styleVariant: .monochrome);
    await linked.save(next);
    expect(await store.load(), next);
    expect(
      FileSystemEntity.typeSync(link.path, followLinks: false),
      FileSystemEntityType.link,
    );
    expect(file.statSync().mode & 0x1ff, 0x1a0);
    expect(
      directory.listSync().where(
        (entry) => entry.path.contains('.remya-settings-'),
      ),
      isEmpty,
    );
  });

  test(
    'failed replacement preserves existing data and cleans staging files',
    () async {
      final blocked = Directory('${directory.path}/blocked')..createSync();
      final sentinel = File('${blocked.path}/keep')..writeAsStringSync('keep');
      await expectLater(
        AppPreferencesFile(File(blocked.path)).save(const AppPreferences()),
        throwsA(isA<FileSystemException>()),
      );
      expect(sentinel.readAsStringSync(), 'keep');
      expect(
        directory.listSync().where(
          (entry) => entry.path.contains('.remya-settings-'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'serialized edits preserve both selections and load on restart',
    () async {
      final controller = AppPreferencesController(
        store: store,
        systemAppearance: FakeSystemAppearance(),
      );
      addTearDown(controller.dispose);
      await Future.wait([
        controller.setThemeMode(.dark),
        controller.setStyleVariant(.vibrant),
        controller.setThemeMode(.light),
      ]);
      expect(controller.errorMessage, isNull);
      expect(controller.isBusy, isFalse);
      expect(
        controller.preferences,
        const AppPreferences(themeMode: .light, styleVariant: .vibrant),
      );
      final restarted = AppPreferencesController(
        store: store,
        systemAppearance: FakeSystemAppearance(),
      );
      addTearDown(restarted.dispose);
      await restarted.reload();
      expect(restarted.preferences, controller.preferences);
    },
  );

  test(
    'invalid external edits retain live state and cannot be overwritten',
    () async {
      final controller = AppPreferencesController(
        store: store,
        systemAppearance: FakeSystemAppearance(),
      );
      addTearDown(controller.dispose);
      await controller.setThemeMode(.dark);
      file.writeAsStringSync('broken = [');
      await controller.reload();
      expect(controller.preferences.themeMode, SystemThemeMode.dark);
      expect(controller.errorMessage, isNotNull);
      await controller.setStyleVariant(.monochrome);
      expect(file.readAsStringSync(), 'broken = [');
      expect(
        controller.preferences.styleVariant,
        DynamicSchemeVariant.expressive,
      );
      await store.save(
        const AppPreferences(themeMode: .dark, styleVariant: .neutral),
      );
      await controller.reload();
      expect(controller.errorMessage, isNull);
      expect(
        controller.preferences,
        const AppPreferences(themeMode: .dark, styleVariant: .neutral),
      );
    },
  );

  test(
    'failed saves and completion after disposal do not replace live state',
    () async {
      final blocked = AppPreferencesController(
        systemAppearance: FakeSystemAppearance(),
        store: AppPreferencesFile(File(directory.path)),
      );
      addTearDown(blocked.dispose);
      await blocked.setThemeMode(.dark);
      expect(blocked.preferences, const AppPreferences());
      expect(blocked.errorMessage, isNotNull);
      final controller = AppPreferencesController(
        store: store,
        systemAppearance: FakeSystemAppearance(),
      );
      final pending = controller.setThemeMode(.dark);
      controller.dispose();
      await pending;
      expect(controller.preferences, const AppPreferences());
    },
  );
  test(
    'system mode is read from the backend without writing at startup',
    () async {
      file.writeAsStringSync(
        'version = 1\n[theme]\nstyle_variant = "neutral"\ntheme_mode = "system"\n',
      );
      final system = FakeSystemAppearance(mode: .dark);
      final controller = AppPreferencesController(
        store: store,
        systemAppearance: system,
      );
      addTearDown(controller.dispose);
      await controller.reload();
      expect(controller.preferences.themeMode, SystemThemeMode.dark);
      expect(controller.preferences.styleVariant, DynamicSchemeVariant.neutral);
      expect(system.applyCalls, 0);
      await controller.setStyleVariant(.vibrant);
      expect(system.applyCalls, 0);
      expect((await store.load())!.themeMode, SystemThemeMode.dark);
      expect(file.readAsStringSync(), isNot(contains('system')));
    },
  );

  test('failed system changes restore the previous app configuration and surface errors', () async {
    final system = FakeSystemAppearance(mode: .dark);
    final controller = AppPreferencesController(
      store: store,
      systemAppearance: system,
    );
    addTearDown(controller.dispose);
    await controller.reload();
    await controller.setStyleVariant(.neutral);
    system.applyError = StateError('GTK configuration is read-only');
    await controller.setThemeMode(.light);
    expect(system.applyCalls, 1);
    expect(controller.preferences.themeMode, SystemThemeMode.dark);
    expect((await store.load())!.themeMode, SystemThemeMode.dark);
    expect((await store.load())!.styleVariant, DynamicSchemeVariant.neutral);
    expect(controller.errorMessage, contains('GTK configuration is read-only'));
  });
}
