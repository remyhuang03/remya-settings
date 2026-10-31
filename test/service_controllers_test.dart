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
  testWidgets(
    'sync spins while pending, blocks repeat clicks and stops on success or failure',
    (tester) async {
      final service = FakeService()..ntp = true;
      final controller = ServiceDateTimeController(service);
      addTearDown(controller.dispose);
      addTearDown(service.close);
      await controller.reload();
      // This control is only displayed when automatic time is enabled.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateTimeScope(
              controller: controller,
              child: const DateTimeSettingControl(syncNowSettingId),
            ),
          ),
        ),
      );
      service.gate = Completer<void>();
      final pending = controller.syncNow();
      await tester.pump();
      final finder = find.byKey(const ValueKey('control-$syncNowSettingId'));
      final button = tester.widget<IconButton>(finder);
      expect(button.tooltip, 'Syncing…');
      expect(button.onPressed, isNull);
      final rotation = button.icon as RotationTransition;
      final before = rotation.turns.value;
      await tester.pump(const Duration(milliseconds: 300));
      expect(rotation.turns.value, isNot(before));
      service.gate!.complete();
      await pending;
      await tester.pumpAndSettle();
      expect(controller.isSyncing, isFalse);
      expect(tester.widget<IconButton>(finder).tooltip, 'Sync now');
      expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
      expect(
        (tester.widget<IconButton>(finder).icon as RotationTransition)
            .turns
            .value,
        0,
      );
      service.fail = true;
      await expectLater(controller.syncNow(), throwsStateError);
      await tester.pumpAndSettle();
      expect(controller.isSyncing, isFalse);
      expect(controller.errorMessage, contains('Write failed'));
      expect(
        (tester.widget<IconButton>(finder).icon as RotationTransition)
            .turns
            .value,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
