import 'support/catalog.dart';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_settings/features/power/presentation/power_page.dart';
import 'package:remya_settings/features/power/presentation/battery_usage_page.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/settings/presentation/settings_category_group.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

class _PowerReadClient extends SettingsClient {
  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async => switch (arguments.single) {
    'power' => {'available': true, 'system': {}, 'saved': {}},
    keepAwakeSettingId => {'value': false},
    _ => {'observations': [], 'next': null},
  };
}

void main() {
  testWidgets(
    'long row labels wrap beside the control until the row is narrow',
    (tester) async {
      Future<(Rect, Rect)> layout(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: .topLeft,
              child: SizedBox(
                width: width,
                child: SettingsRowLayout(
                  left: Text('word ' * 60, key: const ValueKey('label')),
                  right: const SizedBox(
                    key: ValueKey('control'),
                    width: 200,
                    height: 40,
                  ),
                ),
              ),
            ),
          ),
        );
        return (
          tester.getRect(find.byKey(const ValueKey('label'))),
          tester.getRect(find.byKey(const ValueKey('control'))),
        );
      }

      final (wideLabel, wideControl) = await layout(760);
      expect(wideLabel.right, lessThanOrEqualTo(wideControl.left - 16));
      expect(wideControl.right, 760);

      final (narrowLabel, narrowControl) = await layout(420);
      expect(narrowControl.top, greaterThanOrEqualTo(narrowLabel.bottom));
      expect(narrowLabel.width, greaterThan(300));
    },
  );

  testWidgets('Power and sleep links open the implemented pages', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final navigation = ValueNotifier<String?>('power');
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShell(
          catalog: SettingsCatalog.fromJson(readCatalog()),
          navigation: navigation,
          client: _PowerReadClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Energy advice'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-page-power.743773bd')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PowerPage>(find.byType(PowerPage)).page.id,
      'battery-saver',
    );
    navigation.value = null;
    navigation.value = 'power';
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-page-power.03bd05ee')));
    await tester.pumpAndSettle();
    expect(find.byType(BatteryUsagePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'category groups cover the catalog once and use readable distinct colors',
    () {
      final catalog = SettingsCatalog.fromJson(readCatalog());
      final groups = SettingsCategoryGroup.values;
      final ids = groups
          .expand((group) => group.categories(catalog).map((c) => c.id))
          .toList();
      expect(
        ids.toSet(),
        catalog.categories.map((category) => category.id).toSet(),
      );
      expect(ids.length, ids.toSet().length);
      expect(
        groups.map((group) => group.background).toSet().length,
        groups.length,
      );
      for (final group in groups) {
        final contrast =
            (group.background.computeLuminance() + .05) /
            (group.foreground.computeLuminance() + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
    },
  );

  testWidgets('content reserves only the visible status bar height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final statusHeight = ValueNotifier(0.0);
    addTearDown(statusHeight.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShell(
          catalog: SettingsCatalog.fromJson(readCatalog()),
          status: ValueListenableBuilder(
            valueListenable: statusHeight,
            builder: (_, height, _) => SizedBox(height: height),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('settings-main-content'));
    expect(tester.getSize(content).height, 800);
    statusHeight.value = 64;
    await tester.pumpAndSettle();
    expect(tester.getSize(content).height, 736);
    statusHeight.value = 0;
    await tester.pumpAndSettle();
    expect(tester.getSize(content).height, 800);
    expect(tester.takeException(), isNull);
  });
}
