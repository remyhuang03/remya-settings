import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/appearance/data/app_preferences_file.dart';
import 'package:remya_settings/features/appearance/data/system_appearance_backend.dart';
import 'package:remya_settings/features/integration/settings_api.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import 'support/fake_system_appearance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late FakeSystemAppearance backend;
  late AppPreferencesController preferences;
  late SettingsApi api;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync('remya-api-');
    backend = _BackendWithTargets();
    preferences = AppPreferencesController(
      store: AppPreferencesFile(File('${temporary.path}/config.toml')),
      systemAppearance: backend,
    );
    await preferences.reload();
    api = SettingsApi(preferences, await SettingsCatalog.load());
  });
  tearDown(() async {
    await api.close();
    preferences.dispose();
    temporary.deleteSync(recursive: true);
  });

  test('CLI and D-Bus methods share the complete advertised interface', () {
    final methods = api.introspect().single.methods;
    expect(
      methods.map((method) => method.name).toSet(),
      settingsMethods.keys.toSet(),
    );
    for (final method in methods) {
      expect(
        method.inputSignature,
        DBusSignature('s' * settingsMethods[method.name]!),
      );
      expect(method.outputSignature, DBusSignature('s'));
    }
  });

  test(
    'set uses GUI persistence and backend with rollback on failure',
    () async {
      await api.execute('Set', ['themes.material-style-variant', 'vibrant']);
      await api.execute('Set', ['themes.material-theme-mode', 'dark']);
      expect(backend.applyCalls, 1);
      expect((await preferences.store.load())!.themeMode.name, 'dark');
      expect((await api.execute('Get', ['theme']))['theme'], {
        'style_variant': 'vibrant',
        'theme_mode': 'dark',
      });
      backend.applyError = StateError('backend failure');
      await expectLater(
        api.execute('Set', ['themes.material-theme-mode', 'light']),
        throwsStateError,
      );
      expect((await preferences.store.load())!.themeMode.name, 'dark');
    },
  );

  test(
    'invalid and unavailable operations never reach system backend',
    () async {
      final before = preferences.preferences;
      for (final args in [
        ['themes.material-style-variant', 'invalid'],
        ['themes.material-theme-mode', 'system'],
        ['missing-setting', 'true'],
      ]) {
        await expectLater(api.execute('Set', args), throwsArgumentError);
      }
      final list = <dynamic>[];
      String? cursor = '0';
      while (cursor != null) {
        final page = await api.execute('List', [cursor]);
        list.addAll(page['controls'] as List);
        cursor = page['next_cursor'] as String?;
      }
      final unavailable = list.firstWhere(
        (control) => control['availability'] != 'available',
      );
      await expectLater(
        api.execute('Set', [unavailable['id'] as String, 'true']),
        throwsUnsupportedError,
      );
      expect(preferences.preferences, before);
      expect(backend.applyCalls, 0);
      expect(
        list.where((control) => control['availability'] == 'available'),
        hasLength(2),
      );
    },
  );

  test(
    'read, search, reload, and navigation expose existing functionality',
    () async {
      final system = await api.execute('Get', ['system']);
      expect(system['mode'], 'light');
      expect((system['targets'] as List).single['status'], 'detected');
      expect((await api.execute('Get', ['catalog']))['pages'], isNotEmpty);
      expect((await api.execute('Search', ['material']))['pages'], isNotEmpty);
      expect((await api.execute('Reload', []))['theme'], isNotNull);
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel('top.remya.paths'), (
            call,
          ) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('top.remya.paths'),
              null,
            ),
      );
      expect(await api.execute('Open', ['about']), {'opened': 'about'});
      expect(api.navigation.value, 'about');
      expect(calls, ['show']);
      await expectLater(
        api.execute('Open', ['missing-page']),
        throwsArgumentError,
      );
    },
  );
}

class _BackendWithTargets extends FakeSystemAppearance {
  @override
  Future<SystemThemeState> read() async => SystemThemeState(
    mode: mode,
    targets: const [
      ThemeTargetResult(
        name: 'Test toolkit',
        status: .detected,
        detail: 'Isolated backend',
      ),
    ],
  );
}
