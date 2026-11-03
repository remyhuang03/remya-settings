import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/background/application/background_controller.dart';
import 'package:remya_settings/features/background/presentation/background_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

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

Future<void> _pump(WidgetTester tester, BackgroundController controller) async {
  final catalog = SettingsCatalog.fromJson(
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: BackgroundPage(
            page: catalog.page('background'),
            controller: controller,
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
  testWidgets('compositor previews stay disabled inside Advanced', (
    tester,
  ) async {
    final h = _Harness(_state());
    addTearDown(h.controller.dispose);
    await h.controller.reload();
    await _pump(tester, h.controller);
    final control = find.byKey(const ValueKey('background.blur-enabled'));
    expect(control.hitTestable(), findsNothing);
    await tester.ensureVisible(find.text('Advanced'));
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(control);
    final toggle = tester.widget<Switch>(
      find.descendant(of: control, matching: find.byType(Switch)),
    );
    expect(toggle.onChanged, isNull);
    expect(find.text('Planned'), findsWidgets);
    expect(h.writes, isEmpty);
  });
}
