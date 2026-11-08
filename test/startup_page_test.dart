import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/startup/application/startup_controller.dart';
import 'package:remya_settings/features/startup/presentation/startup_page.dart';
import 'package:remya_settings_client/settings_contract.dart';

Map<String, dynamic> _entry(
  String id, {
  bool system = false,
  bool enabled = true,
  String? status = 'running',
}) => {
  'id': '$id.desktop',
  'name': id,
  'comment': 'Description of $id',
  'exec': '/usr/bin/true',
  'icon': null,
  'origin': system ? 'system' : 'user',
  'enabled': enabled,
  'removable': !system,
  'status': status,
};

class _Service extends SettingsClient {
  final writes = <(String, Map<String, dynamic>)>[];
  final resolutions = <String>[];
  final queries = <String>[];
  String? failure;
  Completer<void>? gate;
  Map<String, dynamic> state = {
    'api_version': 1,
    'initialized': true,
    'writable': true,
    'conflict': false,
    'conflicts': <Map<String, dynamic>>[],
    'session_autostart': true,
    'status_error': null,
    'skipped_invalid': 0,
    'error': null,
    'entries': [
      _entry('System app', system: true),
      _entry('My app', enabled: false, status: 'failed'),
    ],
  };
  @override
  Stream<SettingsChange> get changes => const Stream.empty();
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Set') {
      writes.add((
        arguments[0],
        jsonDecode(arguments[1]) as Map<String, dynamic>,
      ));
      await gate?.future;
      if (failure != null) throw StateError(failure!);
    }
    if (method == 'Resolve') {
      resolutions.add(arguments[1]);
      state = {
        ...state,
        'conflict': false,
        'conflicts': <Map<String, dynamic>>[],
      };
    }
    if (arguments.first.startsWith('startup-candidates:')) {
      queries.add(arguments.first.substring(19));
      return {
        'applications': [
          {'id': 'new.desktop', 'name': 'New app', 'icon': null},
        ],
      };
    }
    return state;
  }

  StartupController controller() => StartupController(
    read: readStartup,
    candidates: startupCandidates,
    write: changeStartup,
    resolve: resolveStartup,
  );
}

Future<void> _mount(WidgetTester tester, StartupController controller) async {
  tester.view.physicalSize = const Size(1200, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: StartupPage(controller: controller)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'non-UWSM sessions hide runtime labels and retain the explanation',
    (tester) async {
      final service = _Service();
      service.state['session_autostart'] = false;
      service.state['entries'] = [_entry('My app', status: 'not-started')];
      final controller = service.controller();
      addTearDown(controller.dispose);
      await _mount(tester, controller);
      expect(find.text('Not started'), findsNothing);
      expect(find.text('Last sign-in'), findsNothing);
      expect(
        find.textContaining('This session was not started with UWSM'),
        findsOneWidget,
      );
      service.state['entries'] = [_entry('My app', status: 'running')];
      await controller.reload();
      await tester.pumpAndSettle();
      expect(find.text('Running'), findsNothing);
      expect(find.text('Running: 1'), findsNothing);
    },
  );

  testWidgets('UWSM sessions omit an empty last sign-in heading', (
    tester,
  ) async {
    final service = _Service();
    service.state['entries'] = [_entry('My app', status: 'not-started')];
    final controller = service.controller();
    addTearDown(controller.dispose);
    await _mount(tester, controller);
    expect(find.text('Last sign-in'), findsNothing);
    expect(find.text('Not started'), findsOneWidget);
  });

  testWidgets('entries, summary, origins, statuses and toggle payload', (
    tester,
  ) async {
    final service = _Service();
    final controller = service.controller();
    await _mount(tester, controller);
    expect(find.text('1 of 2 apps start when you sign in'), findsOneWidget);
    expect(find.text('From the system'), findsOneWidget);
    expect(find.text('Added by you'), findsOneWidget);
    expect(find.text('Running: 1'), findsOneWidget);
    expect(
      find.text('Failed'),
      findsNothing,
    ); // Off entries have no row status.
    expect(find.text('Add a custom command'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('startup-toggle-My app.desktop')),
    );
    await tester.pumpAndSettle();
    expect(service.writes.single.$1, 'startup.apps');
    expect(service.writes.single.$2, {'id': 'My app.desktop', 'enabled': true});
  });

  testWidgets('conflict lists both values and routes both resolutions', (
    tester,
  ) async {
    final service = _Service();
    final controller = service.controller();
    void conflict() => service.state = {
      ...service.state,
      'conflict': true,
      'conflicts': [
        {
          'id': 'My app.desktop',
          'name': 'My app',
          'system': false,
          'saved': true,
        },
      ],
    };
    conflict();
    await _mount(tester, controller);
    expect(find.text('My app\nSystem: Off\nSettings: On'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).onChanged, isNull);
    await tester.tap(find.text('Use system configuration'));
    await tester.pumpAndSettle();
    conflict();
    await controller.reload();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply Settings configuration'));
    await tester.pumpAndSettle();
    expect(service.resolutions, ['system', 'settings']);
  });

  testWidgets(
    'command requires both fields and keeps validation errors inline',
    (tester) async {
      final service = _Service();
      final controller = service.controller();
      await _mount(tester, controller);
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      final open = find.widgetWithText(FilledButton, 'Add command');
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      final add = find.byKey(const ValueKey('startup-command-add'));
      expect(tester.widget<FilledButton>(add).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('startup-command-name')),
        'My command',
      );
      expect(tester.widget<FilledButton>(add).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('startup-command-exec')),
        'missing-program',
      );
      await tester.pump();
      service.failure = 'InvalidArgument:Executable not found';
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Executable not found'),
        ),
        findsOneWidget,
      );
      expect(service.writes.last.$1, 'startup.add-command');
      expect(service.writes.last.$2, {
        'name': 'My command',
        'command': 'missing-program',
      });
      service.failure = null;
      await tester.enterText(
        find.byKey(const ValueKey('startup-command-exec')),
        '/usr/bin/true',
      );
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('only removable entries have a removal menu and confirmation', (
    tester,
  ) async {
    final service = _Service();
    final controller = service.controller();
    await _mount(tester, controller);
    expect(find.byTooltip('More options for System app'), findsNothing);
    await tester.tap(find.byTooltip('More options for My app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from startup'));
    await tester.pumpAndSettle();
    expect(find.text('Remove My app from startup?'), findsOneWidget);
    expect(service.writes, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.writes, isEmpty);
    await tester.tap(find.byTooltip('More options for My app'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from startup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(service.writes.single.$1, 'startup.remove');
    expect(service.writes.single.$2, {'id': 'My app.desktop'});
  });

  testWidgets('app picker queries the service and adds selected desktop ID', (
    tester,
  ) async {
    final service = _Service();
    final controller = service.controller();
    await _mount(tester, controller);
    await tester.tap(find.text('Add an app'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(service.queries, ['', 'New']);
    await tester.tap(find.text('New app'));
    await tester.pumpAndSettle();
    expect(service.writes.single.$1, 'startup.add-app');
    expect(service.writes.single.$2, {'application': 'new.desktop'});
  });

  testWidgets(
    'status errors replace chips and session explanation is visible',
    (tester) async {
      final service = _Service();
      service.state = {
        ...service.state,
        'session_autostart': false,
        'status_error': 'User manager unavailable',
      };
      await _mount(tester, service.controller());
      expect(find.text('User manager unavailable'), findsOneWidget);
      expect(
        find.textContaining('This session was not started with UWSM'),
        findsOneWidget,
      );
      expect(find.text('Running: 1'), findsNothing);
    },
  );

  testWidgets(
    'startup route uses the custom page and adapts to narrow windows',
    (tester) async {
      final service = _Service();
      final controller = service.controller();
      service.state['entries'] = [
        for (var i = 0; i < 12; i++) _entry('App $i'),
      ];
      final catalog = SettingsCatalog.fromJson(
        jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StartupScope(
            controller: controller,
            child: SettingsShell(
              catalog: catalog,
              navigation: ValueNotifier('startup'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(StartupPage), findsOneWidget);
      expect(find.text('Added by you'), findsOneWidget);
      tester.view.physicalSize = const Size(430, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'controller retains read failure, busy state and last valid entries',
    () async {
      final service = _Service();
      final controller = service.controller();
      await controller.reload();
      service.gate = Completer();
      final pending = controller.set('startup.apps', {
        'id': 'My app.desktop',
        'enabled': true,
      });
      expect(controller.isBusy, isTrue);
      expect(controller.canChange, isFalse);
      service.gate!.complete();
      await pending;
      expect(controller.isBusy, isFalse);
      final failing = StartupController(
        read: () async => throw StateError('Disconnected'),
        candidates: service.startupCandidates,
        write: service.changeStartup,
        resolve: service.resolveStartup,
      );
      failing.value = controller.value;
      await failing.reload();
      expect(failing.entries.length, 2);
      expect(failing.canChange, isFalse);
      expect(failing.errorMessage, contains('Disconnected'));
    },
  );
}
