import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/date_time/application/date_time_controller.dart';
import 'package:remya_settings/features/date_time/presentation/date_time_settings.dart';
import 'package:remya_settings/features/integration/settings_status.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/appearance/data/app_preferences_file.dart';

import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

import 'support/fake_date_time.dart';
import 'support/fake_system_appearance.dart';

void main() {
  late Directory directory;
  late FakeDateTimeBackend backend;
  late DateTimeController controller;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('remya-datetime-');
    backend = FakeDateTimeBackend();
    controller = DateTimeController(
      backend: backend,
      file: File('${directory.path}/date-time.toml'),
    );
  });
  tearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });

  test('initialization adopts the system, caches options, and retains both sides of conflicts', () async {
    await controller.reload();
    expect(controller.savedTimezone, 'Asia/Taipei');
    expect(backend.writes, 0);
    expect(controller.file.readAsStringSync(), contains('Asia/Taipei'));
    backend.timezone = 'UTC';
    await controller.reload();
    expect(backend.lists, 2);
    expect(controller.hasConflict, isTrue);
    expect(controller.savedTimezone, 'Asia/Taipei');
    await controller.useSystemConfiguration();
    expect(controller.hasConflict, isFalse);
    expect(controller.savedTimezone, 'UTC');
    backend.timezone = 'Europe/London';
    await controller.reload();
    await controller.setTimezone(controller.savedTimezone!);
    expect(backend.timezone, 'UTC');
    expect(controller.hasConflict, isFalse);
  });

  test(
    'invalid input and failures preserve configuration and surface errors',
    () async {
      backend.error = StateError('timedated unavailable');
      await expectLater(controller.reload(), throwsStateError);
      expect(controller.file.existsSync(), isFalse);
      backend.error = null;
      await controller.reload();
      final before = controller.file.readAsStringSync();
      await expectLater(
        controller.setTimezone('Not/AZone'),
        throwsArgumentError,
      );
      for (final value in [
        '2026-02-30T12:00:00',
        '2026-10-30T24:00:00',
        'invalid',
      ]) {
        await expectLater(
          controller.setManualTime(value, 'Asia/Taipei'),
          throwsArgumentError,
        );
      }
      expect(backend.writes, 0);
      backend.timezone = 'UTC';
      await controller.reload();
      backend.error = StateError('Permission denied');
      await expectLater(
        controller.setTimezone('Asia/Taipei'),
        throwsStateError,
      );
      expect(controller.errorMessage, contains('Permission denied'));
      expect(controller.hasConflict, isTrue);
      expect(controller.file.readAsStringSync(), before);
      backend.error = null;
      controller.file.writeAsStringSync('invalid [');
      await expectLater(controller.reload(), throwsA(isA<FormatException>()));
      expect(controller.savedTimezone, 'Asia/Taipei');
      expect(controller.file.readAsStringSync(), 'invalid [');
    },
  );

  test('manual time is an operation, never a persisted clock target', () async {
    await controller.reload();
    await controller.setManualTime('2026-10-30T14:30:00', 'Asia/Taipei');
    expect(backend.lastLocalTime, '2026-10-30T14:30:00');
    expect(controller.state!.ntp, isFalse);
    expect(controller.file.readAsStringSync(), contains('ntp = false'));
    expect(
      controller.file.readAsStringSync(),
      isNot(contains('2026-10-30T14:30:00')),
    );
  });

  test('automatic time, persistent server choices and LC_TIME reconcile independently', () async {
    await controller.reload();
    await controller.setAutomaticTime(false);
    expect(controller.hideManualTime, isFalse);
    await controller.setAutomaticTime(true);
    expect(controller.hideManualTime, isTrue);
    await controller.setTimeServers(['pool.ntp.org']);
    expect(controller.file.readAsStringSync(), contains('pool.ntp.org'));
    await controller.syncNow();
    expect(backend.syncs, 1);
    await controller.setTimeServers([]);
    expect(backend.servers, isEmpty);
    await controller.setTimeLocale('zh_CN.utf8');
    expect(controller.restartSuggested, isTrue);
    controller.deferRestart();
    expect(controller.restartDeferred, isTrue);
    backend.timeLocale = 'C';
    backend.servers = ['time.example.org'];
    await controller.reload();
    expect(controller.hasConflict, isTrue);
    await controller.applySavedConfiguration();
    expect(backend.timeLocale, 'zh_CN.utf8');
    expect(backend.servers, isEmpty);
    expect(controller.hasConflict, isFalse);
    for (final servers in [
      ['https://bad'],
      ['bad name'],
      ['-bad'],
      List.filled(17, 'ntp.org'),
    ]) {
      await expectLater(
        controller.setTimeServers(servers),
        throwsArgumentError,
      );
    }
    await expectLater(
      controller.setTimeLocale('not-installed'),
      throwsArgumentError,
    );
    final before = controller.file.readAsStringSync();
    backend.error = StateError('Authorization canceled');
    await expectLater(
      controller.setTimeServers(['time.example.org']),
      throwsStateError,
    );
    expect(controller.file.readAsStringSync(), before);
  });

  testWidgets(
    'server Default/Custom applies on editing and restart status offers Later',
    (tester) async {
      await tester.runAsync(controller.reload);
      final preferences = AppPreferencesController(
        store: AppPreferencesFile(File('${directory.path}/theme.toml')),
        systemAppearance: FakeSystemAppearance(),
      );
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DateTimeScope(
            controller: controller,
            child: Scaffold(
              body: Column(
                children: [
                  SettingsStatus(
                    preferences: preferences,
                    dateTime: controller,
                  ),
                  const SizedBox(
                    width: 232,
                    child: DateTimeSettingControl(timeServerSettingId),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Default'), findsWidgets);
      final menu = tester.widget<DropdownMenu<bool>>(
        find.byWidgetPredicate((widget) => widget is DropdownMenu<bool>),
      );
      menu.onSelected!(true);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('time-servers')),
        'pool.ntp.org',
      );
      await tester.runAsync(() async {
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(backend.servers, ['pool.ntp.org']);
      await tester.runAsync(() async {
        tester
            .widget<DropdownMenu<bool>>(
              find.byWidgetPredicate((widget) => widget is DropdownMenu<bool>),
            )
            .onSelected!(false);
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(backend.servers, isEmpty);
      await tester.runAsync(() => controller.setTimeLocale('C'));
      await tester.pumpAndSettle();
      expect(find.text('Restart now'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('settings-status-card')))
            .height,
        lessThan(110),
      );
      await tester.tap(find.text('Restart now'));
      await tester.pumpAndSettle();
      expect(
        find.text('Save your work before restarting the system.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(backend.restarts, 0);
      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      expect(find.text('Restart now'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'finite combo, current time, manual dialog and conflict resolution',
    (tester) async {
      backend.ntp = false;
      await tester.runAsync(controller.reload);
      final preferences = AppPreferencesController(
        store: AppPreferencesFile(File('${directory.path}/theme.toml')),
        systemAppearance: FakeSystemAppearance(),
      );
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DateTimeScope(
            controller: controller,
            child: Scaffold(
              body: Column(
                children: [
                  SettingsStatus(
                    preferences: preferences,
                    dateTime: controller,
                  ),
                  const CurrentDateTime(),
                  const SizedBox(
                    width: 232,
                    child: DateTimeSettingControl(timezoneSettingId),
                  ),
                  const DateTimeSettingControl(manualTimeSettingId),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('current-date-time')), findsOneWidget);
      final text = find
          .descendant(
            of: find.byKey(const ValueKey('timezone-combobox')),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(text, 'arbitrary');
      await tester.pumpAndSettle();
      expect(backend.writes, 0);
      expect(find.byKey(const ValueKey('apply-timezone')), findsNothing);
      await tester.enterText(text, 'UTC');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(
          find.widgetWithText(MenuItemButton, 'UTC (GMT+00:00)').last,
        );
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(backend.timezone, 'UTC');
      await tester.tap(
        find.byKey(const ValueKey('control-$manualTimeSettingId')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('manual-date')), findsOneWidget);
      expect(find.byKey(const ValueKey('manual-time')), findsOneWidget);
      expect(find.textContaining('turns off automatic'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('apply-manual-time')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(backend.lastLocalTime, isNotNull);
      backend.timezone = 'Europe/London';
      await tester.runAsync(controller.reload);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Date/time configuration differs'),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('Use system configuration'));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(controller.savedTimezone, 'Europe/London');
      expect(
        find.textContaining('Date/time configuration differs'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  for (final width in [1280.0, 600.0, 360.0]) {
    testWidgets('live date/time controls fit the full shell at $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(controller.reload);
      final catalog = (await tester.runAsync(SettingsCatalog.load))!;
      final navigation = ValueNotifier<String?>('date-time');
      addTearDown(navigation.dispose);
      final preferences = AppPreferencesController(
        store: AppPreferencesFile(File('${directory.path}/theme.toml')),
        systemAppearance: FakeSystemAppearance(),
      );
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: DateTimeScope(
            controller: controller,
            child: SettingsShell(
              catalog: catalog,
              navigation: navigation,
              status: SettingsStatus(
                preferences: preferences,
                dateTime: controller,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Usually no change'), findsOneWidget);
      expect(
        find.textContaining('Synchronized · pool.ntp.org'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey(manualTimeSettingId)), findsNothing);
      final servers = tester.getRect(
        find.byKey(const ValueKey('time-server-mode')),
      );
      final timezone = tester.getRect(
        find.byKey(const ValueKey('timezone-combobox')),
      );
      expect(servers.right, closeTo(timezone.right, 1));
      final sync = tester.widget<IconButton>(
        find.byKey(const ValueKey('control-$syncNowSettingId')),
      );
      expect(sync.tooltip, 'Sync now');
      expect(
        ((sync.icon as RotationTransition).child as Icon).icon,
        Icons.sync_rounded,
      );

      await tester.runAsync(() => controller.setAutomaticTime(false));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey(manualTimeSettingId)), findsOneWidget);
      expect(find.byKey(const ValueKey(timeServerSettingId)), findsNothing);
      expect(find.byKey(const ValueKey(syncNowSettingId)), findsNothing);
      final pane = tester.getRect(
        find.byKey(const ValueKey('settings-main-content')),
      );
      await tester.runAsync(() => controller.setTimeLocale('C'));
      await tester.pumpAndSettle();
      final status = tester.getRect(
        find.byKey(const ValueKey('settings-status-card')),
      );
      expect(status.left, greaterThanOrEqualTo(width < 1000 ? 80 : 280));
      expect(status.right, lessThanOrEqualTo(pane.right));
      expect(status.bottom, lessThanOrEqualTo(pane.bottom));
      expect(
        tester.getRect(find.byKey(const ValueKey('settings-main-content'))),
        pane,
      );

      await tester.ensureVisible(
        find.byKey(const ValueKey('timezone-combobox')),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
