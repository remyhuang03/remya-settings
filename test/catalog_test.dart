import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/settings/presentation/settings_widgets.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

Map<String, dynamic> readCatalog() =>
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
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

  testWidgets(
    'compact actions stay inline when content fits and stack only when narrow',
    (tester) async {
      for (final width in [320.0, 220.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                child: SettingRow(
                  id: 'test-row',
                  label: const Text('Qt 6 Settings'),
                  control: FilledButton(
                    onPressed: () {},
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final text = tester.getRect(find.text('Qt 6 Settings'));
        final button = tester.getRect(find.byType(FilledButton));
        if (width == 320) {
          expect((text.center.dy - button.center.dy).abs(), lessThan(16));
          expect(button.left, greaterThan(text.right));
        } else {
          expect(button.top, greaterThan(text.bottom));
        }
        expect(tester.takeException(), isNull);
      }
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

  test('every added control has a pinned source and stays unavailable', () {
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
      expect(source['url'], contains('/blob/${source['revision']}/'));
      expect(
        catalog.page(entry['page'] as String).controls.map((c) => c.id),
        contains(entry['control']),
      );
      expect(
        addedControls[entry['control']]!.availability,
        SettingAvailability.planned,
      );
    }
    final sourceIds = (raw['sources'] as List).map((s) => s['id']).toSet();
    for (final page in raw['pages'] as List) {
      expect(sourceIds, containsAll(page['sources'] as List));
    }
    expect(
      catalog.search('direct_scanout').map((p) => p.id),
      contains('hypr-render'),
    );
    expect(
      catalog.search('hypridle').map((p) => p.id),
      contains('hypr-idle-listeners'),
    );
    expect(
      catalog.search('window rules').map((p) => p.id),
      contains('hypr-window-rule-props'),
    );
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
