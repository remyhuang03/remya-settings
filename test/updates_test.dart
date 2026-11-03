import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/settings/presentation/settings_row_layout.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/updates/application/updates_controller.dart';
import 'package:remya_settings/features/updates/presentation/updates_page.dart';
import 'package:remya_settings_client/settings_contract.dart';

void main() {
  test(
    'inspection never upgrades and stale snapshots cannot replace new progress',
    () async {
      final writes = <(String, String)>[];
      final controller = UpdatesController(
        read: () async => {'revision': 0, 'available': true, 'phase': 'idle'},
        write: (id, value) async {
          writes.add((id, value));
          return {'revision': 3, 'phase': 'checking', 'busy': true};
        },
      );
      await controller.reload();
      expect(writes, isEmpty);
      await controller.set(updatesCheckSettingId, 'check');
      expect(writes, [(updatesCheckSettingId, 'check')]);
      controller.apply({'revision': 5, 'phase': 'completed', 'busy': false});
      controller.apply({'revision': 4, 'phase': 'checking', 'busy': true});
      expect(controller.busy, false);
      expect(controller.value['phase'], 'completed');
      controller.dispose();
    },
  );

  testWidgets(
    'explicit check, upgrade and retry are in Settings with live output',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final writes = <(String, String)>[];
      final state = <String, dynamic>{
        'available': true,
        'authorized': true,
        'phase': 'idle',
        'revision': 0,
        'checked_at': 1,
        'packages': [
          {'name': 'mesa', 'held': false},
        ],
        'schedule': {'enabled': false, 'time': '03:00'},
        'output': [
          'first line',
          'error: AUR connection refused',
          'latest line',
        ],
      };
      final controller = UpdatesController(
        read: () async => state,
        write: (id, value) async {
          writes.add((id, value));
          return {
            ...state,
            'busy': true,
            'phase': 'upgrading',
            'attempt': 1,
            'revision': 1,
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UpdatesPage(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      expect(find.text('latest line'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('latest line')).dy,
        lessThan(tester.getTopLeft(find.text('first line')).dy),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Update now'));
      await tester.pump();
      expect(writes, [(updatesUpgradeSettingId, 'upgrade')]);
      expect(find.text('Upgrading packages (attempt 1)'), findsOneWidget);
      final check = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Check for updates'),
      );
      expect(check.onPressed, isNull);
      final terminalError = tester.widget<Text>(
        find.text('error: AUR connection refused'),
      );
      expect(terminalError.style?.fontFamily, 'monospace');
      expect(
        find.ancestor(
          of: find.text('error: AUR connection refused'),
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
      final switches = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      expect(
        switches
            .firstWhere(
              (item) => (item.title as Text).data == 'Include held packages',
            )
            .onChanged,
        isNull,
      );
      expect(
        switches
            .firstWhere(
              (item) => (item.title as Text).data == 'Retry after failure',
            )
            .onChanged,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets(
    'no misleading install action before checks and automatic schedule starts off',
    (tester) async {
      final writes = <(String, String)>[];
      final state = <String, dynamic>{
        'available': true,
        'authorized': true,
        'schedule': {'enabled': false, 'time': '03:00'},
      };
      final controller = UpdatesController(
        read: () async => state,
        write: (id, value) async {
          writes.add((id, value));
          return {
            ...state,
            'schedule': {'enabled': true, 'time': '03:00'},
          };
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UpdatesPage(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Update now'), findsNothing);
      expect(find.text('Daily update time'), findsNothing);
      final automatic = find.widgetWithText(
        SwitchListTile,
        'Automatic updates',
      );
      expect(tester.widget<SwitchListTile>(automatic).value, false);
      await tester.tap(automatic);
      await tester.pumpAndSettle();
      expect(writes, [(updatesAutomaticSettingId, 'true')]);
      expect(find.text('Daily update time'), findsOneWidget);
      expect(find.text('Active hours'), findsNothing);
      final activeHours = SettingsCatalog.fromJson(
        jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      ).page('active-hours');
      expect(activeHours.availability, SettingAvailability.planned);
      expect(activeHours.controls.length, 3);
      expect(
        activeHours.controls.every(
          (control) => control.availability == SettingAvailability.planned,
        ),
        true,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets('status and actions share a row whenever natural widths fit', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final canInstall in [false, true]) {
      for (final width in [1200.0, 520.0, 320.0]) {
        await tester.binding.setSurfaceSize(Size(width, 1400));
        final state = <String, dynamic>{
          'available': true,
          'authorized': true,
          'phase': 'idle',
          'checked_at': canInstall ? 1 : null,
          'packages': canInstall
              ? [
                  {'name': 'mesa', 'held': false},
                ]
              : [],
        };
        final controller = UpdatesController(
          read: () async => state,
          write: (_, _) async => state,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: UpdatesPage(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final header = find.byKey(const ValueKey('updates-status-actions'));
        final layout = tester.widget<SettingsRowLayout>(header);
        final status = tester.getRect(find.byWidget(layout.children.first));
        final actions = tester.getRect(find.byWidget(layout.children.last));
        final widthAvailable = tester.getSize(header).width;
        final fits = status.width + 16 + actions.width <= widthAvailable;
        if (width == 1200) expect(fits, true);
        if (fits) {
          expect((status.center.dy - actions.center.dy).abs(), lessThan(2));
          expect(actions.left, greaterThan(status.right));
        } else {
          expect(actions.top, greaterThan(status.bottom));
        }
        expect((status.left - tester.getRect(header).left).abs(), lessThan(1));
        expect(
          (actions.right - tester.getRect(header).right).abs(),
          lessThan(1),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    }
  });
  testWidgets(
    'production WIP preserves readable output and disables every update control',
    (tester) async {
      final writes = <(String, String)>[];
      final state = <String, dynamic>{
        'available': false,
        'work_in_progress': true,
        'reason': 'Incomplete and unverified; execution paused.',
        'checked_at': 1,
        'packages': [
          {'name': 'mesa', 'held': false},
        ],
        'schedule': {'enabled': true, 'time': '03:00', 'editable': true},
        'output': ['existing diagnostic output'],
      };
      final controller = UpdatesController(
        read: () async => state,
        write: (id, value) async {
          writes.add((id, value));
          return state;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UpdatesPage(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Work in progress'), findsOneWidget);
      expect(find.text('existing diagnostic output'), findsOneWidget);
      for (final button in tester.widgetList<ButtonStyleButton>(
        find.byType(FilledButton),
      )) {
        expect(button.onPressed, isNull);
      }
      for (final button in tester.widgetList<ButtonStyleButton>(
        find.byType(OutlinedButton),
      )) {
        expect(button.onPressed, isNull);
      }
      for (final toggle in tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      )) {
        expect(toggle.onChanged, isNull);
      }
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Automatic updates'),
            )
            .value,
        true,
      );
      expect(writes, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
