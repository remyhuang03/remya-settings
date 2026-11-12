import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/power/presentation/power_page.dart';
import 'package:remya_settings/features/power/presentation/battery_usage_page.dart';
import 'package:remya_settings_client/settings_contract.dart';
import 'package:remya_settings/features/settings/presentation/settings_row_layout.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/settings/presentation/settings_category_group.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

Map<String, dynamic> readCatalog() =>
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

class _PowerReadClient extends SettingsClient {
  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async => switch (arguments.single) {
    'power' => {'available': true, 'system': {}, 'saved': {}},
    keepAwakeSettingId => {'value': false},
    _ => {'observations': [], 'next': null},
  };
}

void main() {
  testWidgets(
    'long row labels wrap beside the control until the row is narrow',
    (tester) async {
      Future<(Rect, Rect)> layout(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: .topLeft,
              child: SizedBox(
                width: width,
                child: SettingsRowLayout(
                  left: Text('word ' * 60, key: const ValueKey('label')),
                  right: const SizedBox(
                    key: ValueKey('control'),
                    width: 200,
                    height: 40,
                  ),
                ),
              ),
            ),
          ),
        );
        return (
          tester.getRect(find.byKey(const ValueKey('label'))),
          tester.getRect(find.byKey(const ValueKey('control'))),
        );
      }

      final (wideLabel, wideControl) = await layout(760);
      expect(wideLabel.right, lessThanOrEqualTo(wideControl.left - 16));
      expect(wideControl.right, 760);

      final (narrowLabel, narrowControl) = await layout(420);
      expect(narrowControl.top, greaterThanOrEqualTo(narrowLabel.bottom));
      expect(narrowLabel.width, greaterThan(300));
    },
  );

  testWidgets('Power and sleep links open the implemented pages', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final navigation = ValueNotifier<String?>('power');
    addTearDown(navigation.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShell(
          catalog: SettingsCatalog.fromJson(readCatalog()),
          navigation: navigation,
          client: _PowerReadClient(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Energy advice'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('open-page-power.743773bd')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PowerPage>(find.byType(PowerPage)).page.id,
      'battery-saver',
    );
    navigation.value = null;
    navigation.value = 'power';
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-page-power.03bd05ee')));
    await tester.pumpAndSettle();
    expect(find.byType(BatteryUsagePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'Camera catalog implements supported controls and removes discarded pages',
    () {
      final catalog = SettingsCatalog.fromJson(readCatalog());
      final ids = catalog.pages.map((p) => p.id).toSet();
      expect(ids.intersection({'pen', 'pen-shortcuts', 'recovery'}), isEmpty);
      final camera = catalog.page('cameras');
      expect(camera.controls.map((c) => c.id).toSet(), {
        'cameras.devices',
        'cameras.brightness',
        'cameras.contrast',
        'cameras.saturation',
        'cameras.sharpness',
        'cameras.reset',
      });
      expect(
        camera.controls.every((c) => c.availability.name == 'available'),
        isTrue,
      );
    },
  );

  test(
    'category groups cover the catalog once and use readable distinct colors',
    () {
      final catalog = SettingsCatalog.fromJson(readCatalog());
      final groups = SettingsCategoryGroup.values;
      final ids = groups.expand((group) => group.ids).toList();
      expect(
        ids.toSet(),
        catalog.categories.map((category) => category.id).toSet(),
      );
      expect(ids.length, ids.toSet().length);
      expect(
        groups.map((group) => group.background).toSet().length,
        groups.length,
      );
      for (final group in groups) {
        final contrast =
            (group.background.computeLuminance() + .05) /
            (group.foreground.computeLuminance() + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
    },
  );

  testWidgets('grouped categories navigate in wide and compact sidebars', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [1200.0, 800.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsShell(
            key: ValueKey(width),
            catalog: SettingsCatalog.fromJson(readCatalog()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final group in SettingsCategoryGroup.values) {
        expect(
          find.byKey(ValueKey('home-group-${group.name}')),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const ValueKey('nav-network')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('nav-page-network-status')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('single-page categories omit redundant page navigation', (
    tester,
  ) async {
    final navigation = ValueNotifier<String?>('updates');
    addTearDown(navigation.dispose);
    final singlePageCatalog = readCatalog();
    (singlePageCatalog['pages'] as List).removeWhere(
      (page) => page['id'] == 'active-hours',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShell(
          catalog: SettingsCatalog.fromJson(singlePageCatalog),
          navigation: navigation,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-page-updates')), findsNothing);
    navigation.value = 'sound-volume';
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-page-sound-volume')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-page-volume-mixer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('content reserves only the visible status bar height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final statusHeight = ValueNotifier(0.0);
    addTearDown(statusHeight.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShell(
          catalog: SettingsCatalog.fromJson(readCatalog()),
          status: ValueListenableBuilder(
            valueListenable: statusHeight,
            builder: (_, height, _) => SizedBox(height: height),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final content = find.byKey(const ValueKey('settings-main-content'));
    expect(tester.getSize(content).height, 800);
    statusHeight.value = 64;
    await tester.pumpAndSettle();
    expect(tester.getSize(content).height, 736);
    statusHeight.value = 0;
    await tester.pumpAndSettle();
    expect(tester.getSize(content).height, 800);
    expect(tester.takeException(), isNull);
  });

  test(
    'every source route and backup leaf has a renderable catalog target',
    () {
      final catalog = SettingsCatalog.fromJson(readCatalog());
      final coverage = jsonDecode(
        File('docs/windows-settings-coverage.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        catalog.pages.expand((p) => p.controls).map((c) => c.kind).toSet(),
        SettingKind.values.toSet(),
      );
      for (final entry in coverage['uris'] as List) {
        expect(
          catalog.page(entry['page'] as String).windowsUris,
          contains(entry['uri']),
        );
      }
      for (final entry in coverage['backupSettings'] as List) {
        final page = catalog.page(entry['page'] as String);
        if (entry['coverage'] == 'control') {
          expect(page.controls.map((c) => c.id), contains(entry['control']));
        }
      }
      for (final category in catalog.categories) {
        final original = catalog.pages.where((p) => p.category == category.id);
        final ordered = catalog.inCategory(category.id);
        final regular = original.where((p) => !p.id.endsWith('-more'));
        final more = original.where((p) => p.id.endsWith('-more'));
        expect(ordered, orderedEquals([...regular, ...more]));
      }
      for (final page in catalog.pages) {
        expect(page.controls, isNotEmpty);
        for (final control in page.controls) {
          expect(control.reason, isNotEmpty);
        }
      }
      expect(
        catalog.search('Night light').map((p) => p.id),
        contains('night-light'),
      );
      expect(
        catalog.search('ms-settings:network-wifi').map((p) => p.id),
        contains('wifi'),
      );
      expect(catalog.search('definitely-no-such-setting'), isEmpty);
    },
  );

  test(
    'invalid schema values and navigation references fail before rendering',
    () {
      final json = readCatalog();
      final control =
          ((json['pages'] as List).first['sections'] as List)
                  .first['controls'][0]
              as Map<String, dynamic>;
      control['value'] = -1;
      expect(() => SettingsCatalog.fromJson(json), throwsFormatException);
      final badLink = readCatalog();
      (badLink['pages'] as List).first['children'] = ['unknown-page'];
      expect(() => SettingsCatalog.fromJson(badLink), throwsFormatException);
      final duplicate = readCatalog();
      (duplicate['pages'] as List).add((duplicate['pages'] as List).first);
      expect(() => SettingsCatalog.fromJson(duplicate), throwsFormatException);
    },
  );

  final raw = _readJson('assets/settings/catalog.json');
  final catalog = SettingsCatalog.fromJson(raw);
  final coverage = _readJson('docs/hyprland-settings-coverage.json');

  test('Hyprland additions retain every baseline setting and category', () {
    expect(
      catalog.categories.map((c) => c.id),
      containsAll(coverage['baselineCategories'] as List),
    );
    expect(
      catalog.pages.map((p) => p.id),
      containsAll(coverage['baselinePages'] as List),
    );
    expect(
      catalog.pages.expand((p) => p.controls).map((c) => c.id),
      containsAll(coverage['baselineControls'] as List),
    );
  });

  test('every added control has a pinned source and verified availability', () {
    final sources = {
      for (final source in coverage['sources'] as List)
        source['id'] as String: source as Map<String, dynamic>,
    };
    final addedPages = (coverage['addedPages'] as List).cast<String>().toSet();
    final evidence = (coverage['controls'] as List)
        .cast<Map<String, dynamic>>();
    final evidenced = evidence.map((e) => e['control']).toSet();
    // Cursor mixes Hyprland and Windows-reference controls, so it is not an added page.
    final addedControls = {
      for (final page in catalog.pages)
        for (final control in page.controls)
          if (addedPages.contains(page.id) || evidenced.contains(control.id))
            control.id: control,
    };
    expect(
      evidence.map((e) => e['control']).toSet(),
      addedControls.keys.toSet(),
    );
    for (final entry in evidence) {
      final source = sources[entry['source']];
      expect(source, isNotNull, reason: entry['control'] as String);
      expect(source!['revision'], matches(RegExp(r'^[0-9a-f]{40}$')));
      if (entry['availability'] == 'available') {
        expect(entry['verification'], isNotEmpty);
      }
      expect(source['url'], contains('/blob/${source['revision']}/'));
      expect(
        catalog.page(entry['page'] as String).controls.map((c) => c.id),
        contains(entry['control']),
      );
      expect(
        addedControls[entry['control']]!.availability,
        entry['availability'] == 'available'
            ? SettingAvailability.available
            : SettingAvailability.planned,
      );
    }
    final sourceIds = (raw['sources'] as List).map((s) => s['id']).toSet();
    for (final page in raw['pages'] as List) {
      expect(sourceIds, containsAll(page['sources'] as List));
    }
    expect(
      catalog.search('direct_scanout').map((p) => p.id),
      contains('graphics'),
    );
    expect(catalog.search('lock screen').map((p) => p.id), contains('power'));
    expect(
      catalog.search('window rules').map((p) => p.id),
      contains('window-rules'),
    );
  });

  test('folded compositor controls stay in their owner’s collapsed Advanced section', () {
    final standalone = (coverage['addedPages'] as List).cast<String>().toSet();
    for (final entry
        in (coverage['controls'] as List).cast<Map<String, dynamic>>()) {
      final pageId = entry['page'] as String;
      // Cursor already groups both reference catalogs in its existing layout.
      if (standalone.contains(pageId) ||
          pageId == 'cursor' ||
          entry['availability'] == 'available') {
        continue;
      }
      final page = catalog.page(pageId);
      final section = page.sections.singleWhere(
        (s) => s.controls.any((c) => c.id == entry['control']),
      );
      expect(section.title, 'Advanced', reason: entry['control'] as String);
      expect(section.collapsed, isTrue, reason: entry['control'] as String);
    }
  });

  test(
    'the human progress tracker covers every current control exactly once',
    () {
      final tracker = File('docs/settings-implementation-progress.md')
          .readAsStringSync();
      final rows = RegExp(
        r'^\| .*? \| `([^`]+)` \| .*? \| (已实现|未实现|不适用) \| .*? \|$',
        multiLine: true,
      ).allMatches(tracker).toList();
      final controls = catalog.pages.expand((p) => p.controls).toList();
      expect(rows.length, controls.length);
      final statuses = {for (final row in rows) row[1]!: row[2]!};
      expect(statuses.length, controls.length);
      for (final control in controls) {
        expect(statuses[control.id], switch (control.availability) {
          .available => '已实现',
          .planned => '未实现',
          .unsupported => '不适用',
        }, reason: control.id);
      }
      final headings = RegExp(
        r'^### .* — `([^`]+)`$',
        multiLine: true,
      ).allMatches(tracker).map((m) => m[1]).toList();
      expect(headings.length, catalog.pages.length);
      expect(headings.toSet(), catalog.pages.map((p) => p.id).toSet());
    },
  );
}
