import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/background/application/background_controller.dart';
import 'package:remya_settings/features/background/presentation/background_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

Map<String, dynamic> _state({
  String kind = 'image',
  bool conflict = false,
  String? blocked,
  bool withVideo = false,
}) => {
  'initialized': true,
  'conflict': conflict,
  'write_blocked': blocked,
  'monitors': ['DP-1', 'DP-2'],
  'warnings': <String>[],
  'names': {
    '/own/a.png': 'a.png',
    '/own/b.png': 'b.png',
    '/own/v.mp4': 'v.mp4',
  },
  'previews': <String, String>{},
  'error': null,
  'system': {'kind': kind, 'images': []},
  'saved': {
    'kind': kind,
    'images': [
      {'monitor': '*', 'path': '/own/a.png', 'fit': 'cover'},
      {'monitor': 'DP-2', 'path': '/own/b.png', 'fit': 'tile'},
    ],
    'video': withVideo || kind == 'video'
        ? {'path': '/own/v.mp4', 'fit': 'fill', 'pause': 'keep'}
        : null,
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

Future<void> _pump(
  WidgetTester tester,
  BackgroundController controller, {
  BackgroundFilePicker? pick,
  bool expanded = false,
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
            page: catalog.page('background'),
            controller: controller,
            expandAdvanced: expanded,
            pickFile: pick ?? (_) async => '/picked/photo.png',
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

  testWidgets('choosing a file sends the selected display', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness(_state());
    await h.controller.reload();
    await _pump(tester, h.controller);
    expect(find.text('a.png'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('background-browse')));
    await tester.pumpAndSettle();
    final (id, value) = h.writes.single;
    expect(id, backgroundFileSettingId);
    // The fixture's displays differ, so the first one starts selected on its own.
    expect(jsonDecode(value), {'path': '/picked/photo.png', 'display': 'DP-1'});
  });

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

  testWidgets('video needs a file first and then hides per-display options', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness(_state());
    await h.controller.reload();
    bool? askedVideo;
    await _pump(
      tester,
      h.controller,
      pick: (video) async {
        askedVideo = video;
        return null;
      },
    );
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(askedVideo, isTrue);
    expect(h.writes, isEmpty, reason: 'cancelling the dialog changes nothing');

    h.state = _state(kind: 'video');
    await h.controller.reload();
    await tester.pumpAndSettle();
    expect(find.text('Display'), findsNothing);
    expect(find.text('v.mp4'), findsOneWidget);
    expect(find.text('Tile'), findsNothing);
  });

  testWidgets('a remembered video switches without a new selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness(_state(withVideo: true));
    await h.controller.reload();
    await _pump(
      tester,
      h.controller,
      pick: (_) => throw StateError('no dialog expected'),
    );
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(h.writes.single, (backgroundKindSettingId, 'video'));
  });

  testWidgets('conflicts and read-only files disable changes', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final state in [
      _state(conflict: true),
      _state(blocked: 'line 1: unsupported setting source'),
    ]) {
      final h = _Harness(state);
      await h.controller.reload();
      await _pump(tester, h.controller);
      await tester.tap(find.byKey(const ValueKey('background-browse')));
      await tester.pumpAndSettle();
      expect(h.writes, isEmpty);
    }
  });

  testWidgets('advanced is collapsed unless its old page was requested', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness(_state());
    await h.controller.reload();
    await _pump(tester, h.controller);
    expect(find.byKey(const ValueKey('background-splash')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, h.controller, expanded: true);
    await tester.tap(find.byKey(const ValueKey('background-splash')));
    await tester.pumpAndSettle();
    expect(h.writes.single, (splashSettingId, 'false'));
  });

  testWidgets('settings that do not apply are hidden', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Finder row(String id) => find.byKey(ValueKey(id));
    Map<String, dynamic> off() {
      final state = _state();
      (state['saved'] as Map)['splash'] = {
        'enabled': false,
        'offset': 20,
        'opacity': 0.8,
      };
      return state;
    }

    final h = _Harness(_state());
    await h.controller.reload();
    await _pump(tester, h.controller, expanded: true);
    expect(row(backgroundPauseSettingId), findsNothing);
    expect(row(splashOffsetSettingId), findsOneWidget);
    expect(
      tester.getSize(row('background-splash-offset')).height,
      lessThan(80),
    );
    expect(find.text('20 px'), findsOneWidget);

    h.state = off();
    await h.controller.reload();
    await tester.pumpAndSettle();
    expect(row(splashSettingId), findsOneWidget);
    expect(row(splashOffsetSettingId), findsNothing);
    expect(row(splashOpacitySettingId), findsNothing);

    h.state = _state(kind: 'video');
    await h.controller.reload();
    await tester.pumpAndSettle();
    expect(row(backgroundPauseSettingId), findsOneWidget);
    expect(row(splashSettingId), findsNothing);
    expect(row(backgroundDisplaySettingId), findsNothing);
  });

  testWidgets('warnings are shown at minimum width without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final h = _Harness(
      _state()..['warnings'] = ['Several hyprpaper instances'],
    );
    await h.controller.reload();
    await _pump(tester, h.controller);
    expect(find.byKey(const ValueKey('background-warning')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'the theme contract carries a seed without changing the theme schema',
    () {
      final config = ThemeConfig.fromMap({
        'version': 1,
        'theme': {'style_variant': 'vibrant', 'theme_mode': 'dark'},
      });
      expect(config.seedColor, isNull);
      expect(
        (config.toMap()['theme'] as Map).keys,
        isNot(contains('seed_color')),
      );
      final seeded = config.withSeed('#123456');
      expect(
        (seeded.toMap()['theme'] as Map).keys,
        isNot(contains('seed_color')),
      );
      expect(seeded.toJson(), contains('#123456'));
      expect(RemyaTheme.fromConfig(seeded).seedColor, const Color(0xFF123456));
      expect(RemyaTheme.fromConfig(config).seedColor, RemyaTheme.defaultSeed);
      expect(ThemeConfig.seedFromAccent({'color': '#ABCDEF'}), '#ABCDEF');
      expect(ThemeConfig.seedFromAccent({'color': 'red'}), isNull);
      expect(
        ThemeConfig.seedFromAccentFile(
          'version = 1\nsource = "custom"\ncolor = "#010203"\n',
        ),
        '#010203',
      );
    },
  );
}
