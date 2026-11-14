import 'support/catalog.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_settings/features/updates/application/updates_controller.dart';
import 'package:remya_settings/features/updates/presentation/active_hours_page.dart';
import 'package:remya_settings/features/updates/presentation/updates_page.dart';
import 'package:remya_client/settings_contract.dart';

/// The switch in the setting row titled [title].
Finder _switch(String title) => find.descendant(
  of: find.widgetWithText(SettingRow, title),
  matching: find.byType(Switch),
);

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
        'missing': [],
        'aur': true,
        'eligible': true,
        'phase': 'idle',
        'revision': 0,
        'checked_at': 1,
        'packages': [
          {'name': 'linux', 'source': 'repository', 'held': true},
          {'name': 'mesa', 'source': 'repository', 'held': false},
          {'name': 'yay-bin', 'source': 'AUR', 'held': false},
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
      expect(find.text('2 repository updates'), findsOneWidget);
      expect(find.text('1 AUR updates'), findsOneWidget);
      expect(find.text('Held'), findsOneWidget);
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
      expect(
        tester.widget<Switch>(_switch('Include held packages')).onChanged,
        isNull,
      );
      expect(
        tester.widget<Switch>(_switch('Retry after failure')).onChanged,
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
      expect(find.textContaining('once per inactive period'), findsNothing);
      final automatic = _switch('Automatic updates');
      expect(tester.widget<Switch>(automatic).value, false);
      await tester.tap(automatic);
      await tester.pumpAndSettle();
      expect(writes, [(updatesAutomaticSettingId, 'true')]);
      expect(find.textContaining('once per inactive period'), findsOneWidget);
      final activeHours = SettingsCatalog.fromJson(readCatalog())
          .page('active-hours');
      expect(activeHours.availability, SettingAvailability.available);
      expect(activeHours.controls.map((control) => control.id), [
        activeHoursStartSettingId,
        activeHoursEndSettingId,
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets(
    'a missing system updater shows its install command and still allows checks',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(720, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final writes = <(String, String)>[];
      final state = <String, dynamic>{
        'available': false,
        'missing': [],
        'updater': 'missing',
        'reason': 'The system updater is missing.',
        'install_command':
            'sudo python ../remya-core/tool/install_system_updater.py',
        'checked_at': 1,
        'eligible': true,
        'packages': [
          {'name': 'mesa', 'source': 'repository', 'held': false},
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
      expect(find.text('The system updater is missing.'), findsOneWidget);
      expect(
        find.text('sudo python ../remya-core/tool/install_system_updater.py'),
        findsOneWidget,
      );
      expect(find.text('Update now'), findsNothing);
      expect(find.text('existing diagnostic output'), findsOneWidget);
      for (final title in ['Include held packages', 'Retry after failure']) {
        expect(tester.widget<Switch>(_switch(title)).onChanged, isNull);
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Check for updates'));
      await tester.pump();
      expect(writes, [(updatesCheckSettingId, 'check')]);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
  testWidgets(
    'active hours show saved times and lock while the file is invalid',
    (tester) async {
      for (final editable in [true, false]) {
        final state = <String, dynamic>{
          'schedule': {
            'active_start': '09:30',
            'active_end': '01:00',
            'editable': editable,
          },
        };
        final controller = UpdatesController(
          read: () async => state,
          write: (_, _) async => state,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: ActiveHoursPage(controller: controller),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('09:30'), findsOneWidget);
        expect(find.text('01:00'), findsOneWidget);
        for (final button in tester.widgetList<OutlinedButton>(
          find.byType(OutlinedButton),
        )) {
          expect(button.onPressed == null, !editable);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      }
    },
  );
}
