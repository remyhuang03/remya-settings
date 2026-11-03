import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/sound/application/sound_controller.dart';
import 'package:remya_settings/features/sound/presentation/sound_page.dart';

Map<String, dynamic> state() => {
  'available': true,
  'initialized': true,
  'conflict': false,
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

class _Client extends SettingsClient {
  final calls = <(String, List<String>)>[];
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add((method, arguments));
    return state();
  }
}

void main() {
  test('Sound defaults to combined controls before mixer and devices', () {
    final catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final pages = catalog.inCategory('sound');
    expect(pages.map((page) => page.id), [
      'sound-volume',
      'volume-mixer',
      'sound-devices',
    ]);
    expect(pages.map((page) => page.title), [
      'Output & input',
      'Volume mixer',
      'Devices',
    ]);
    expect(
      pages.first.controls.where((c) => c.availability == .available).length,
      6,
    );
  });
  test('Sound client preserves the generic versioned contract', () async {
    final client = _Client();
    addTearDown(client.close);
    await client.readSound();
    await client.changeSound(soundOutputVolumeSettingId, {'percent': 50});
    await client.resolveSound('system');
    expect(client.calls.map((c) => [c.$1, ...c.$2]), [
      ['Get', 'sound'],
      ['Set', 'sound.output-volume', '{"percent":50}'],
      ['Resolve', 'sound', 'system'],
    ]);
  });
  test('an older periodic read cannot replace a completed write', () async {
    final pending = Completer<Map<String, dynamic>>();
    final updated = state()..['conflict'] = true;
    final controller = SoundController(
      read: () => pending.future,
      write: (_, _) async => updated,
      resolve: (_) async => updated,
    );
    addTearDown(controller.dispose);
    final loading = controller.reload();
    await controller.set('sound.output-muted', {'muted': true});
    pending.complete(state());
    await loading;
    expect(controller.hasConflict, isTrue);
  });
  late Map<String, dynamic> snapshot;
  late List<(String, Map)> writes;
  late List<String> resolutions;
  late SoundController controller;
  setUp(() {
    snapshot = state();
    writes = [];
    resolutions = [];
    controller = SoundController(
      read: () async => snapshot,
      write: (id, value) async {
        writes.add((id, jsonDecode(value) as Map));
        return snapshot;
      },
      resolve: (source) async {
        resolutions.add(source);
        return snapshot;
      },
    );
  });
  tearDown(() => controller.dispose());
  Future<void> host(WidgetTester tester, String page) async {
    final catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
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
    expect(find.text('Volume: 50%'), findsOneWidget);
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
  testWidgets(
    'conflicts offer both resolutions and mixer streams remain ephemeral',
    (tester) async {
      snapshot['conflict'] = true;
      await host(tester, 'volume-mixer');
      expect(
        find.text('Sound settings differ from saved Settings'),
        findsOneWidget,
      );
      expect(find.text('Player'), findsOneWidget);
      await tester.tap(find.text('Use system configuration'));
      await tester.pumpAndSettle();
      expect(resolutions, ['system']);
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
    },
  );
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
      resolve: (_) async => snapshot,
    );
    addTearDown(failing.dispose);
    await failing.reload();
    final previous = failing.value;
    await failing.set('sound.output-volume', {'percent': 25});
    expect(failing.value, same(previous));
    expect(failing.errorMessage, contains('device removed'));
    expect(failing.isBusy, isFalse);
  });
}
