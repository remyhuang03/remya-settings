import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/integration/settings_status.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/system_information/application/hostname_controller.dart';
import 'package:remya_settings_client/settings_contract.dart';

Map<String, dynamic> observed(String name, {bool conflict = false}) => {
  'static_hostname': name,
  'hostname': name,
  'saved_static_hostname': conflict ? 'saved-name' : name,
  'initialized': true,
  'conflict': conflict,
  'error': null,
};

void main() {
  final catalog = SettingsCatalog.fromJson(
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  test(
    'hostname validation, conflict choices and failed changes preserve names',
    () async {
      for (final invalid in [
        '',
        'UPPER',
        'two words',
        '-leading',
        'trailing-',
        'a.b',
        '中文',
        'a' * 64,
      ]) {
        expect(validateHostname(invalid), isNotNull);
      }
      for (final valid in ['pc', 'pc-42', 'a' * 63]) {
        expect(validateHostname(valid), isNull);
      }
      var state = observed('external', conflict: true);
      final choices = <String>[];
      final controller = HostnameController(
        read: () async => state,
        renameName: (_) async => throw StateError('denied'),
        resolve: (source) async {
          choices.add(source);
          return state = observed(
            source == 'system' ? 'external' : 'saved-name',
          );
        },
      );
      addTearDown(controller.dispose);
      await controller.reload();
      expect(controller.hasConflict, isTrue);
      expect(controller.canRename, isFalse);
      await controller.useSystemConfiguration();
      expect(controller.hasConflict, isFalse);
      expect(controller.staticHostname, 'external');
      state = observed('external', conflict: true);
      await controller.reload();
      await controller.applySavedConfiguration();
      expect(controller.staticHostname, 'saved-name');
      expect(choices, ['system', 'settings']);
      await expectLater(controller.rename('new-name'), throwsStateError);
      expect(controller.staticHostname, 'saved-name');
      expect(controller.errorMessage, contains('denied'));
      expect(controller.isBusy, isFalse);
    },
  );

  testWidgets(
    'inline rename validates, preserves failure and refreshes after success at 360',
    (tester) async {
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var state = observed('original');
      var deny = true;
      var calls = 0;
      final controller = HostnameController(
        read: () async => state,
        renameName: (name) async {
          calls++;
          if (deny) throw StateError('Authorization denied');
          return state = observed(name);
        },
        resolve: (source) async =>
            state = observed(source == 'system' ? 'external' : 'saved-name'),
      );
      addTearDown(controller.dispose);
      final navigation = ValueNotifier<String?>('system-information');
      addTearDown(navigation.dispose);
      await tester.pumpWidget(
        HostnameScope(
          controller: controller,
          child: MaterialApp(
            home: SettingsShell(
              catalog: catalog,
              navigation: navigation,
              topStatus: HostnameStatus(controller: controller),
              systemInformation: () async => {
                'values': {
                  for (final id in systemInformationSettingIds)
                    id: {'value': 'Detected $id', 'error': null},
                },
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Planned'), findsNothing);
      await tester.ensureVisible(find.byTooltip('Rename device'));
      await tester.tap(find.byTooltip('Rename device'));
      await tester.pumpAndSettle();
      expect(find.text('Rename this device'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('hostname-input')),
        'Bad Name',
      );
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Rename'))
            .onPressed,
        isNull,
      );
      expect(calls, 0);
      await tester.enterText(
        find.byKey(const ValueKey('hostname-input')),
        'new-host',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Authorization denied'), findsOneWidget);
      expect(controller.staticHostname, 'original');
      deny = false;
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Rename this device'), findsNothing);
      expect(find.text('new-host'), findsOneWidget);
      state = observed('external', conflict: true);
      await controller.reload();
      await tester.pumpAndSettle();
      expect(find.text('Configuration differs'), findsOneWidget);
      expect(find.text('Apply Settings configuration'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.byType(HostnameStatus)).dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(find.byKey(const ValueKey('settings-main-content')))
              .dy,
        ),
      );
      await tester.tap(find.text('Use system configuration'));
      await tester.pumpAndSettle();
      expect(controller.hasConflict, isFalse);
      expect(find.text('Configuration differs'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
