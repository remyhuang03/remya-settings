import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/background/application/background_controller.dart';
import 'package:remya_settings/features/background/presentation/background_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings_client/settings_contract.dart';

Map<String, dynamic> _state() => {
  'initialized': true,
  'conflict': false,
  'write_blocked': null,
  'monitors': ['DP-1', 'DP-2'],
  'warnings': <String>[],
  'names': {
    '/own/a.png': 'a.png',
    '/own/b.png': 'b.png',
    '/own/v.mp4': 'v.mp4',
  },
  'previews': <String, String>{},
  'error': null,
  'system': {'kind': 'image', 'images': []},
  'saved': {
    'kind': 'image',
    'images': [
      {'monitor': '*', 'path': '/own/a.png', 'fit': 'cover'},
      {'monitor': 'DP-2', 'path': '/own/b.png', 'fit': 'tile'},
    ],
    'video': null,
    'splash': {'enabled': true, 'offset': 20, 'opacity': 0.8},
  },
};

class _Harness {
  _Harness(this.state);
  Map<String, dynamic> state;
  final writes = <(String, String)>[];
  final resolved = <String>[];
  Object? failure;
  late final controller = BackgroundController(
    read: () async => state,
    write: (id, value) async {
      if (failure case final error?) throw error;
      writes.add((id, value));
      return state;
    },
    resolve: (source) async {
      resolved.add(source);
      return state;
    },
  );
}

/// Serves the `desktop` option group and records writes.
class _DesktopClient extends SettingsClient {
  Map<String, dynamic> options = {
    'background.blur-enabled': false,
    'background.blur-variant': 0,
    'background.blur-size': 8,
    'background.blur-passes': 1,
    'background.fallback-color': '#141318',
    'background.hide-logo': true,
  };
  final calls = <List<String>>[];

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    if (method == 'Set') options[arguments[0]] = jsonDecode(arguments[1]);
    return {'options': options, 'conflict': false, 'conflicts': <String>[]};
  }
}

Future<void> _pump(
  WidgetTester tester,
  BackgroundController controller, {
  SettingsClient? client,
}) async {
  final catalog = SettingsCatalog.fromJson(
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BackgroundPage(
            catalog: catalog,
            page: catalog.page('background'),
            controller: controller,
            client: client,
            pickFile: (_) async => '/picked/photo.png',
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    'the controller exposes per-display values and keeps failures',
    () async {
      final h = _Harness(_state());
      await h.controller.reload();
      expect(h.controller.pathFor('DP-2'), '/own/b.png');
      expect(h.controller.pathFor('DP-1'), '/own/a.png');
      expect(h.controller.fitFor('DP-2'), 'tile');
      expect(h.controller.nameOf('/own/b.png'), 'b.png');

      h.failure = StateError('hyprpaper is not running');
      await h.controller.set(backgroundFitSettingId, 'contain');
      expect(h.controller.errorMessage, contains('not running'));
      expect(h.controller.isBusy, isFalse);
      h.failure = null;
      await h.controller.retry();
      expect(h.controller.errorMessage, isNull);
      expect(h.writes.single, (backgroundFitSettingId, 'contain'));

      await h.controller.useSystemConfiguration();
      await h.controller.applySavedConfiguration();
      expect(h.resolved, ['system', 'settings']);
    },
  );

  test('equal displays group, and clicks move between group and display', () {
    final h = _Harness(_state());
    final same = {'path': '/own/a.png', 'fit': 'cover'};
    h.controller.apply({
      'monitors': ['A', 'B', 'C'],
      'saved': {
        'kind': 'image',
        'images': [
          {'monitor': '*', ...same},
          {'monitor': 'B', 'path': '/own/b.png', 'fit': 'cover'},
          {'monitor': 'C', ...same},
        ],
      },
    });
    final groups = h.controller.displayGroups;
    expect(groups, [
      ['A', 'C'],
      ['B'],
    ]);
    Set<String> click(Set<String> from, String display) =>
        BackgroundController.nextDisplaySelection(groups, from, display);
    expect(click({'B'}, 'A'), {'A', 'C'});
    expect(click({'A', 'C'}, 'C'), {'C'});
    expect(click({'C'}, 'C'), {'A', 'C'});
    expect(click({'C'}, 'A'), {'A', 'C'});
    expect(click({'A', 'C'}, 'B'), {'B'});
    expect(click({'B'}, 'B'), {'B'});

    expect(h.controller.validDisplaySelection({}), {'A', 'C'});
    expect(h.controller.validDisplaySelection({'C'}), {'C'});
    expect(h.controller.validDisplaySelection({'A', 'B'}), {'A', 'C'});
    expect(h.controller.validDisplaySelection({'gone'}), {'A', 'C'});
  });

  testWidgets('the display group sets the scope of a change', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final state = _state();
    state['monitors'] = ['A', 'B', 'C'];
    (state['saved'] as Map)['images'] = [
      {'monitor': '*', 'path': '/own/a.png', 'fit': 'cover'},
      {'monitor': 'C', 'path': '/own/b.png', 'fit': 'cover'},
    ];
    final h = _Harness(state);
    await h.controller.reload();
    await _pump(tester, h.controller);
    Future<Object?> browse() async {
      await tester.tap(find.byKey(const ValueKey('background-browse')));
      await tester.pumpAndSettle();
      return jsonDecode(h.writes.last.$2)['display'];
    }

    Future<void> click(String display) async {
      await tester.tap(find.byKey(ValueKey('background-display-$display')));
      await tester.pump();
    }

    expect(await browse(), ['A', 'B']);
    await click('B');
    expect(await browse(), 'B');
    await click('C');
    expect(await browse(), 'C');
    expect(find.text('b.png'), findsOneWidget);

    state['monitors'] = ['A', 'B'];
    await h.controller.reload();
    await tester.pumpAndSettle();
    expect(await browse(), '*');

    state['monitors'] = ['A'];
    await h.controller.reload();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('background-display-A')), findsNothing);
    expect(await browse(), '*');
  });
  testWidgets('blur options follow the switch', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness(_state());
    final client = _DesktopClient();
    addTearDown(h.controller.dispose);
    await h.controller.reload();
    await _pump(tester, h.controller, client: client);
    expect(find.byKey(const ValueKey('background.blur-size')), findsNothing);

    final toggle = find.descendant(
      of: find.byKey(const ValueKey('background.blur-enabled')),
      matching: find.byType(Switch),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Set', 'background.blur-enabled', 'true']);
    expect(find.byKey(const ValueKey('background.blur-size')), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('background.blur-noise')), findsOneWidget);
    expect(find.text('#141318'), findsOneWidget);
    expect(h.writes, isEmpty);
  });
}
