import 'dart:io';

import 'package:remya_settings/features/integration/settings_scheduler.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/date_time/presentation/date_time_settings.dart';
import 'package:remya_settings/features/integration/service_controllers.dart';
import 'package:remya_settings/features/date_time/application/date_time_controller.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

class FakeService extends SettingsClient {
  final calls = <(String, List<String>)>[];
  Completer<void>? gate;
  String locale = '';
  bool fail = false;
  bool ntp = false;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add((method, arguments));
    if (method == 'Set') {
      await gate?.future;
      if (fail) throw StateError('Write failed');
      if (arguments[0] == timeLocaleSettingId) locale = '';
    }
    if (arguments.firstOrNull == 'timezones') {
      return {
        'options': ['UTC'],
        'labels': {'UTC': 'UTC (GMT+00:00)'},
      };
    }
    if (arguments.firstOrNull == 'time-locales') {
      return {
        'options': ['', 'en_US.utf8'],
      };
    }
    return {
      'unix_micros': '1793408409410434',
      'local_time': '2026-10-31T09:00:09',
      'timezone': 'UTC',
      'ntp': ntp,
      'ntp_synchronized': ntp,
      'time_servers': <String>[],
      'active_time_server': '',
      'sync_error': null,
      'time_locale': locale,
      'saved_timezone': 'UTC',
      'saved': {'timezone': 'UTC'},
      'conflict': false,
      'restart_suggested': method == 'Set',
    };
  }
}

void main() {
  test('GUI delegates normalized locale and conflict operations without local persistence', () async {
    final service = FakeService();
    final controller = ServiceDateTimeController(service);
    addTearDown(controller.dispose);
    addTearDown(service.close);
    await controller.reload();
    await controller.setTimeLocale('en_US.utf8');
    expect(controller.state!.timeLocale, '');
    expect(controller.restartSuggested, isTrue);
    expect(service.calls.where((call) => call.$1 == 'Set').single.$2, [
      timeLocaleSettingId,
      'en_US.utf8',
    ]);
    await controller.useSystemConfiguration();
    expect(service.calls.where((call) => call.$1 == 'Resolve').single.$2, [
      'date-time',
      'system',
    ]);
  });
  test(
    'manual time hides immediately while automatic-time write is pending',
    () async {
      final service = FakeService();
      final controller = ServiceDateTimeController(service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      await controller.reload();
      service.gate = Completer<void>();
      final pending = controller.setAutomaticTime(true);
      expect(controller.hideManualTime, isTrue);
      expect(controller.isBusy, isTrue);
      service.gate!.complete();
      await pending;
      expect(controller.isBusy, isFalse);
    },
  );
  test('retry repeats the failed write rather than only refreshing', () async {
    final service = FakeService();
    final controller = ServiceDateTimeController(service);
    addTearDown(controller.dispose);
    addTearDown(service.close);
    await controller.reload();
    service.fail = true;
    await expectLater(controller.setTimeLocale('en_US.utf8'), throwsStateError);
    service.fail = false;
    await controller.retry();
    final writes = service.calls.where((call) => call.$1 == 'Set').toList();
    expect(writes.length, 2);
    expect(writes.first.$1, writes.last.$1);
    expect(writes.first.$2, writes.last.$2);
    expect(controller.errorMessage, isNull);
  });

  testWidgets('writes and refreshes preserve dropdown state, focus and draft', (
    tester,
  ) async {
    final service = FakeService();
    final controller = ServiceDateTimeController(service);
    addTearDown(controller.dispose);
    addTearDown(service.close);
    await controller.reload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DateTimeScope(
            controller: controller,
            child: const Column(
              children: [
                DateTimeSettingControl(timezoneSettingId),
                DateTimeSettingControl(timeLocaleSettingId),
                DateTimeSettingControl(automaticTimeSettingId),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final zone = find.byKey(const ValueKey('timezone-combobox'));
    final locale = find.byKey(const ValueKey('time-locale-combobox'));
    final zoneState = tester.state(zone);
    final localeState = tester.state(locale);
    final field = find.descendant(of: zone, matching: find.byType(TextField));
    await tester.enterText(field, 'draft');
    await tester.pumpAndSettle();
    final editable = find.descendant(
      of: zone,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    service.gate = Completer<void>();
    final pending = controller.setTimeLocale('en_US.utf8');
    await tester.pump();
    expect(identical(tester.state(zone), zoneState), isTrue);
    expect(identical(tester.state(locale), localeState), isTrue);
    expect(tester.widget<DropdownMenu<String>>(zone).enabled, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    await controller.reload();
    await tester.pump();
    expect(controller.isBusy, isTrue);
    expect(tester.widget<EditableText>(editable).controller.text, 'draft');
    service.gate!.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(identical(tester.state(zone), zoneState), isTrue);
    expect(identical(tester.state(locale), localeState), isTrue);
    expect(tester.widget<EditableText>(editable).focusNode.hasFocus, isTrue);
    expect(tester.widget<EditableText>(editable).controller.text, 'draft');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'debug launcher opens a local executable without an installed service',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'remya-debug-launch-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final executable = File('${directory.path}/settings with spaces')
        ..writeAsStringSync('#!/bin/sh\nprintf started > "\$0.started"\n');
      expect(
        (await Process.run('chmod', ['+x', '--', executable.path])).exitCode,
        0,
      );
      await openRemyaSettings(debugExecutable: executable);
      final marker = File('${executable.path}.started');
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!marker.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(marker.readAsStringSync(), 'started');
    },
  );

  test('missing debug build reports the build command instead of using release config', () async {
    await expectLater(
      openRemyaSettings(debugExecutable: File('/nonexistent/remya_settings')),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'build guidance',
          contains('fvm flutter build linux --debug'),
        ),
      ),
    );
  });

  test('runs independent checks concurrently, coalesces rounds and isolates failure', () async {
    final gate = Completer<void>();
    var first = 0;
    var second = 0;
    final scheduler = SettingsScheduler([
      () async {
        first++;
        await gate.future;
        throw StateError('one backend failed');
      },
      () async {
        second++;
        await gate.future;
      },
    ]);
    final round = scheduler.refresh();
    expect(identical(round, scheduler.refresh()), isTrue);
    expect(first, 1);
    expect(second, 1);
    gate.complete();
    await round;
    await scheduler.refresh();
    expect(first, 2);
    expect(second, 2);
    scheduler.dispose();
    await scheduler.refresh();
    expect(first, 2);
  });

  test(
    'service snapshots and signals use the same validated theme contract',
    () async {
      final client = _Client();
      final preferences = SettingsThemeController.service(client: client);
      await preferences.start();
      expect(preferences.error, isNull);
      expect(preferences.theme.mode, ThemeMode.dark);
      expect(preferences.theme.styleVariant, DynamicSchemeVariant.neutral);
      client.current = const ThemeConfig(styleVariant: 'vibrant').toMap();
      client.events.add((topic: 'theme', value: client.current));
      expect(preferences.theme.mode, ThemeMode.light);
      expect(preferences.theme.styleVariant, DynamicSchemeVariant.vibrant);
      final valid = preferences.theme;
      client.events.add((topic: 'theme', value: {'version': 999}));
      expect(preferences.error, isNotNull);
      expect(preferences.theme, same(valid));
      await preferences.reload();
      expect(preferences.error, isNull);
      client.failure = StateError('Service unavailable');
      await preferences.reload();
      expect(preferences.error, isNotNull);
      expect(preferences.theme.styleVariant, DynamicSchemeVariant.vibrant);
      client.failure = null;
      await preferences.reload();
      expect(preferences.error, isNull);
      preferences.dispose();
      expect(client.closed, isTrue);
    },
  );
}

class _Client extends SettingsClient {
  final events = StreamController<SettingsChange>.broadcast(sync: true);
  Map<String, dynamic> current = const ThemeConfig(
    styleVariant: 'neutral',
    mode: 'dark',
  ).toMap();
  Object? failure;
  bool closed = false;

  @override
  Stream<SettingsChange> get changes => events.stream;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (failure case final error?) throw error;
    return current;
  }

  @override
  Future<void> close() async {
    closed = true;
    await events.close();
    await super.close();
  }
}
