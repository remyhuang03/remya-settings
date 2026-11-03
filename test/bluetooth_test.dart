import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/bluetooth/application/bluetooth_controller.dart';
import 'package:remya_settings/features/bluetooth/presentation/bluetooth_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_content.dart';

const adapter = '/org/bluez/hci0';
Map<String, dynamic> state({
  bool powered = true,
  bool paired = true,
  int? battery,
  Map? prompt,
}) => {
  'available': true,
  'error': null,
  'scanning': <String>[],
  'operation': null,
  'prompt': prompt,
  'adapters': [
    {
      'id': adapter,
      'name': 'Test adapter',
      'address': '00:11:22:33:44:55',
      'powered': powered,
      'discoverable': false,
    },
  ],
  'devices': [
    {
      'id': '$adapter/dev_test',
      'adapter': adapter,
      'name': 'Keyboard',
      'address': 'AA:BB:CC:DD:EE:FF',
      'icon': 'input-keyboard',
      'paired': paired,
      'connected': false,
      'battery': battery,
    },
  ],
};
Future<void> refresh(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  late Map<String, dynamic> current;
  late List<(String, Map)> writes;
  late BluetoothController controller;
  setUp(() {
    current = state();
    writes = [];
    controller = BluetoothController(
      read: () async => current,
      write: (id, value) async {
        writes.add((id, jsonDecode(value) as Map));
        return current;
      },
    )..value = current;
  });
  tearDown(() => controller.dispose());
  Widget host() => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: BluetoothPage(controller: controller)),
    ),
  );

  testWidgets(
    'power hides dependent controls and keeps paired device readout',
    (tester) async {
      current = state(powered: false);
      await tester.pumpWidget(host());
      await refresh(tester);
      expect(find.text('Keyboard'), findsOneWidget);
      expect(find.text('Connect'), findsNothing);
      expect(find.text('Add device'), findsNothing);
      expect(find.text('Adapter'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await refresh(tester);
      expect(writes.last.$1, 'bluetooth.enabled');
      expect(writes.last.$2, {'adapter': adapter, 'enabled': true});
    },
  );
  testWidgets('temporary discoverability is visible without opening Advanced', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await refresh(tester);
    final button = find.text('Discoverable for 60 seconds');
    await tester.ensureVisible(button);
    expect(button.hitTestable(), findsOneWidget);
    expect(find.text('Discoverable: No'), findsOneWidget);
    await tester.tap(button);
    await refresh(tester);
    expect(writes.first.$1, 'bluetooth.discoverable');
    await tester.tap(find.text('Done'));
    await refresh(tester);
  });
  testWidgets('battery is optional and removal requires confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await refresh(tester);
    expect(find.textContaining('Battery:'), findsNothing);
    current = state(battery: 0);
    controller.apply(current);
    await tester.pump();
    expect(find.text('Battery: 0%'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await refresh(tester);
    expect(writes, isEmpty);
    expect(
      find.text('You will need to pair this device again to use it.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await refresh(tester);
    expect(writes.last.$1, 'bluetooth.forget');
  });
  testWidgets(
    'scan, PIN validation, submit, cancel and stop on dialog dismissal',
    (tester) async {
      current = state(paired: false);
      await tester.pumpWidget(host());
      await refresh(tester);
      await tester.tap(find.text('Add device'));
      await refresh(tester);
      expect(writes.last.$1, 'bluetooth.scan');
      await tester.tap(find.text('Pair'));
      await refresh(tester);
      expect(writes.last.$1, 'bluetooth.pair');
      current = {
        ...current,
        'operation': {'kind': 'pair', 'status': 'running'},
        'prompt': {'id': 7, 'kind': 'RequestPinCode'},
      };
      controller.apply(current);
      await refresh(tester);
      await tester.tap(find.text('Submit'));
      await refresh(tester);
      expect(find.text('Enter 1 to 16 letters or digits'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await refresh(tester);
      expect(writes.last.$1, 'bluetooth.respond');
      expect(writes.last.$2, {
        'adapter': adapter,
        'request': 7,
        'accept': true,
        'pin': '1234',
      });
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await refresh(tester);
      expect(writes.map((w) => w.$1), contains('bluetooth.cancel'));
      expect(writes.last.$1, 'bluetooth.scan');
      expect(writes.last.$2, {'adapter': adapter, 'enabled': false});
    },
  );
  testWidgets('confirmation and displayed keyboard passkey remain explicit', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await refresh(tester);
    await tester.tap(find.text('Add device'));
    await refresh(tester);
    current = {
      ...current,
      'operation': {'kind': 'pair', 'status': 'running'},
      'prompt': {'id': 9, 'kind': 'RequestConfirmation', 'code': '001234'},
    };
    controller.apply(current);
    await refresh(tester);
    expect(find.text('001234'), findsOneWidget);
    expect(writes.where((w) => w.$1 == 'bluetooth.respond'), isEmpty);
    await tester.tap(find.text('Reject'));
    await refresh(tester);
    expect(writes.last.$2['accept'], false);
    current = {
      ...current,
      'prompt': {
        'id': 10,
        'kind': 'DisplayPasskey',
        'code': '001234',
        'entered': 2,
      },
    };
    controller.apply(current);
    await refresh(tester);
    expect(find.text('Digits entered: 2'), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);
    await tester.tap(find.text('Done'));
    await refresh(tester);
  });
  testWidgets('error retry recovers and layout works at 360 pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    current = {...state(), 'error': 'Permission denied'};
    await tester.pumpWidget(host());
    await refresh(tester);
    expect(find.text('Permission denied'), findsOneWidget);
    current = state();
    await tester.tap(find.text('Retry'));
    await refresh(tester);
    expect(find.text('Permission denied'), findsNothing);
    await tester.tap(find.text('Add device'));
    await refresh(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await refresh(tester);
  });
  testWidgets('airplane Bluetooth entry navigates to the implemented page', (
    tester,
  ) async {
    final catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    String? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsDetail(
              catalog: catalog,
              page: catalog.page('airplane'),
              onPage: (p) => opened = p.id,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await refresh(tester);
    expect(opened, 'bluetooth');
  });
  testWidgets('missing service, no adapter and hardware block are explicit', (
    tester,
  ) async {
    current = {
      'available': false,
      'adapters': <Map>[],
      'devices': <Map>[],
      'error': 'Bluetooth service is not running',
    };
    await tester.pumpWidget(host());
    await refresh(tester);
    expect(find.text('Bluetooth service is not running'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNothing);
    current = {'available': true, 'adapters': <Map>[], 'devices': <Map>[]};
    controller.apply(current);
    await refresh(tester);
    expect(find.text('No Bluetooth adapter found.'), findsOneWidget);
    current = state(powered: false);
    (current['adapters'] as List).first['hardware_blocked'] = true;
    controller.apply(current);
    await refresh(tester);
    expect(find.text('Blocked by a hardware switch'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });
  test(
    'adapter selection releases the previous adapter and stays session local',
    () async {
      current = state();
      (current['adapters'] as List).add({
        'id': '/org/bluez/hci1',
        'name': 'Second adapter',
        'powered': true,
      });
      controller.apply(current);
      controller.selectAdapter('/org/bluez/hci1');
      await Future<void>.delayed(Duration.zero);
      expect(controller.adapter?['id'], '/org/bluez/hci1');
      expect(writes.last.$1, 'bluetooth.scan');
      expect(writes.last.$2, {'adapter': adapter, 'enabled': false});
      await controller.scan();
      expect(writes.last.$2['adapter'], '/org/bluez/hci1');
    },
  );
  test('failed writes preserve last valid system state', () async {
    final failing = BluetoothController(
      read: () async => state(),
      write: (_, _) async => throw Exception('Denied'),
    )..value = state();
    await failing.set('bluetooth.enabled', {'enabled': false});
    expect(failing.powered, true);
    expect(failing.errorMessage, contains('Denied'));
    expect(failing.sending, false);
    failing.dispose();
  });
}
