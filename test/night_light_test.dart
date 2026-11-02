import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/night_light/application/night_light_controller.dart';
import 'package:remya_settings/features/night_light/presentation/night_light_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:material_ui/material_ui.dart';

Map<String, dynamic> _state({
  bool enabled = true,
  bool schedule = false,
  bool conflict = false,
}) => {
  'running': true,
  'enabled': enabled,
  'schedule': schedule,
  'conflict': conflict,
  'temperature': 2600,
  'start': schedule ? '19:00' : null,
  'end': schedule ? '06:30' : null,
  'saved': {'temperature': 2600, 'enabled': enabled},
  'system': {'temperature': conflict ? 4000 : 2600, 'enabled': enabled},
  'write_blocked': null,
  'error': null,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SettingsPageSpec> page() async =>
      (await SettingsCatalog.load()).page('night-light');

  NightLightController controller(
    Map<String, dynamic> value, {
    List<String>? writes,
    Object? failure,
  }) => NightLightController(
    read: () async => value,
    write: (id, next) async {
      if (failure != null) throw failure;
      writes?.add('$id=$next');
      return value;
    },
    resolve: (_) async => value,
  );

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  testWidgets(
    'toggle writes and schedule times stay hidden without a schedule',
    (tester) async {
      final writes = <String>[];
      final spec = await tester.runAsync(page);
      await pump(
        tester,
        NightLightPage(
          page: spec!,
          controller: controller(_state(), writes: writes),
        ),
      );
      await tester.pump();
      expect(find.text('Start time'), findsNothing);
      expect(find.text('Timing'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('$nightLightEnabledId-switch')),
      );
      await tester.pump();
      expect(writes, ['$nightLightEnabledId=false']);
    },
  );

  testWidgets('a schedule shows its times and the HDR note appears', (
    tester,
  ) async {
    final spec = await tester.runAsync(page);
    await pump(
      tester,
      NightLightPage(
        page: spec!,
        controller: controller(_state(schedule: true)),
        hdrActive: true,
      ),
    );
    await tester.pump();
    expect(find.text('19:00'), findsOneWidget);
    expect(find.text('06:30'), findsOneWidget);
    expect(find.textContaining('HDR'), findsOneWidget);
  });

  testWidgets('a conflict disables changes', (tester) async {
    final spec = await tester.runAsync(page);
    final night = controller(_state(conflict: true));
    await pump(tester, NightLightPage(page: spec!, controller: night));
    await tester.pump();
    expect(night.canChange, isFalse);
    expect(night.conflictSummary, contains('4000 K'));
    final toggle = tester.widget<Switch>(
      find.byKey(const ValueKey('$nightLightEnabledId-switch')),
    );
    expect(toggle.onChanged, isNull);
  });

  test('a failed write stays visible', () async {
    final night = controller(_state(), failure: 'boom');
    await night.reload();
    await night.set(nightLightEnabledId, 'false');
    expect(night.errorMessage, 'boom');
  });

  test('sunset to sunrise stays planned', () async {
    final spec = await page();
    final timing = spec.controls.firstWhere((c) => c.id == nightLightTimingId);
    expect(timing.availability, isNot(SettingAvailability.available));
  });
}
