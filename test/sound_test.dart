import 'support/catalog.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/sound/application/sound_controller.dart';
import 'package:remya_settings/features/sound/presentation/sound_page.dart';
import 'package:remya_client/settings_contract.dart';

class _FakeDesktopClient extends SettingsClient {
  _FakeDesktopClient(this.state);
  Map<String, dynamic> state;
  final calls = <List<String>>[];

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> args = const [],
  ]) async {
    calls.add([method, ...args]);
    if (method == 'Set') {
      (state['options'] as Map)[args[0]] = jsonDecode(args[1]);
    }
    return state;
  }
}

Map<String, dynamic> state() => {
  'available': true,
  'error': null,
  'system': {
    'default_output': 'speakers',
    'default_input': 'microphone',
    'devices': [
      {
        'name': 'speakers',
        'index': 1,
        'description': 'Speakers',
        'direction': 'output',
        'preferences': {
          'channels': [32768, 32768],
          'muted': false,
        },
        'rate': 48000,
        'channels': 2,
        'state': 'Running',
      },
      {
        'name': 'microphone',
        'index': 2,
        'description': 'Microphone',
        'direction': 'input',
        'preferences': {
          'channels': [65536],
          'muted': false,
        },
        'rate': 48000,
        'channels': 1,
        'state': 'Idle',
      },
    ],
    'streams': [
      {
        'index': 3,
        'client': 4,
        'name': 'Music',
        'application': 'Player',
        'direction': 'output',
        'device': 'speakers',
        'preferences': {
          'channels': [65536, 65536],
          'muted': false,
        },
        'has_volume': true,
        'volume_writable': true,
      },
    ],
  },
};

void main() {
  test('an older periodic read cannot replace a completed write', () async {
    final pending = Completer<Map<String, dynamic>>();
    final updated = state()..['error'] = 'write readback failed';
    final controller = SoundController(
      read: () => pending.future,
      write: (_, _) async => updated,
    );
    addTearDown(controller.dispose);
    final loading = controller.reload();
    await controller.set('sound.output-muted', {'muted': true});
    pending.complete(state());
    await loading;
    expect(controller.errorMessage, 'write readback failed');
  });
  late Map<String, dynamic> snapshot;
  late List<(String, Map)> writes;
  late SoundController controller;
  setUp(() {
    snapshot = state();
    writes = [];
    controller = SoundController(
      read: () async => snapshot,
      write: (id, value) async {
        writes.add((id, jsonDecode(value) as Map));
        return snapshot;
      },
    );
  });
  tearDown(() => controller.dispose());
  Future<void> host(WidgetTester tester, String page) async {
    final catalog = SettingsCatalog.fromJson(readCatalog());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SoundPage(controller: controller, page: catalog.page(page)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('output and microphone controls send real scoped operations', (
    tester,
  ) async {
    await host(tester, 'sound-volume');
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Volume'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(writes.single.$1, 'sound.output-muted');
    expect(writes.single.$2, {
      'direction': 'output',
      'name': 'speakers',
      'muted': true,
    });
    expect(find.text('Mute microphone'), findsOneWidget);
    expect(find.textContaining('48000 Hz'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Mute microphone'));
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(writes.last.$1, 'sound.input-muted');
    expect(writes.last.$2, {
      'direction': 'input',
      'name': 'microphone',
      'muted': true,
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('external changes refresh live controls without conflicts', (
    tester,
  ) async {
    await host(tester, 'sound-volume');
    snapshot = state();
    final output = (snapshot['system'] as Map)['devices'][0] as Map;
    output['preferences'] = {
      'channels': [16384, 16384],
      'muted': true,
    };
    await controller.reload();
    await tester.pumpAndSettle();
    expect(find.text('25%'), findsOneWidget);
    expect(find.text('Use system configuration'), findsNothing);
    expect(find.text('Apply saved Settings'), findsNothing);
    expect(controller.canChange, isTrue);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(writes.single.$1, 'sound.output-muted');
    expect(writes.single.$2['muted'], isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('mixer streams use current stream identity', (tester) async {
    await host(tester, 'volume-mixer');
    expect(find.text('Player'), findsOneWidget);
    await tester.ensureVisible(find.text('Mute'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(writes.single.$1, 'sound.stream-muted');
    expect(writes.single.$2, {
      'direction': 'output',
      'index': 3,
      'client': 4,
      'muted': true,
    });
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Sound pages fit a narrow viewport with actual device readouts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final page in ['sound-volume', 'sound-devices', 'volume-mixer']) {
      await host(tester, page);
      expect(tester.takeException(), isNull, reason: page);
      await tester.pumpWidget(const SizedBox());
    }
  });
  test('failed changes retain observed state and show the error', () async {
    final failing = SoundController(
      read: () async => snapshot,
      write: (_, _) async => throw StateError('device removed'),
    );
    addTearDown(failing.dispose);
    await failing.reload();
    final previous = failing.value;
    await failing.set('sound.output-volume', {'percent': 25});
    expect(failing.value, same(previous));
    expect(failing.errorMessage, contains('device removed'));
    expect(failing.isBusy, isFalse);
  });
  testWidgets(
    'compositor bell switches between default, off and custom audio files',
    (tester) async {
      final catalog = SettingsCatalog.fromJson(readCatalog());
      final client = _FakeDesktopClient({
        'options': {'sound.compositor-bell': 'default'},
        'system': {'sound.compositor-bell': 'none'},
        'saved': {'sound.compositor-bell': 'default'},
        'conflict': false,
        'conflicts': <String>[],
        'write_blocked': null,
        'error': null,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SoundPage(
                controller: controller,
                page: catalog.page('sound-volume'),
                catalog: catalog,
                client: client,
                pickBellFile: () async => '/tmp/chime.ogg',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Compositor bell sound (bell_sound)'), findsOneWidget);

      await tester.ensureVisible(find.text('Off'));
      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      expect(client.calls.last, ['Set', 'sound.compositor-bell', '"none"']);

      await tester.tap(find.text('Custom'));
      await tester.pumpAndSettle();
      expect(client.calls.last, [
        'Set',
        'sound.compositor-bell',
        '"/tmp/chime.ogg"',
      ]);
      expect(find.text('File: /tmp/chime.ogg'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sound.compositor-bell-browse')),
        findsOneWidget,
      );

      client.state = {
        ...client.state,
        'conflict': true,
        'conflicts': ['sound.compositor-bell'],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SoundPage(
                key: const ValueKey('sound-bell-conflict'),
                controller: controller,
                page: catalog.page('sound-volume'),
                catalog: catalog,
                client: client,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Compositor bell sound (bell_sound): system Off, Settings Default',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
