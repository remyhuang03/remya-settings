import 'package:remya_settings_client/settings_contract.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/display/application/display_controller.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

Map<String, dynamic> readCatalog() =>
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>;

Map<String, dynamic> _readJson(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

void main() {
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
      final removedPages = (coverage['removedPages'] as List).cast<String>();
      for (final entry in coverage['uris'] as List) {
        if (removedPages.contains(entry['page'])) continue;
        expect(
          catalog.page(entry['page'] as String).windowsUris,
          contains(entry['uri']),
        );
      }
      for (final entry in coverage['backupSettings'] as List) {
        if (removedPages.contains(entry['page'])) continue;
        final page = catalog.page(entry['page'] as String);
        if (entry['coverage'] == 'control') {
          expect(page.controls.map((c) => c.id), contains(entry['control']));
        }
      }
      for (final id in removedPages) {
        expect(() => catalog.page(id), throwsStateError);
        expect(
          catalog.pages.any((page) => page.children.contains(id)),
          isFalse,
        );
      }
      expect(catalog.search('Energy recommendations'), isEmpty);
      expect(catalog.search('Multitasking'), isEmpty);
      for (final page in catalog.pages) {
        expect(page.controls, isNotEmpty);
        expect(page.availability == .available, page.id == 'about');
        for (final control in page.controls) {
          expect(
            control.availability == .available,
            const {
              'themes.material-style-variant',
              'themes.material-theme-mode',
              'date-time.fb2a23dc',
              'date-time.6422d209',
              'date-time.db451de3',
              'date-time.098d06ec',
              'date-time.7e33a213',
              'date-time.format',
              ...displaySettingIds,
              ...systemInformationSettingIds,
              hostnameSettingId,
            }.contains(control.id),
          );
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
    final retired = coverage['retired'] as Map<String, dynamic>;
    final retiredPages = (retired['pages'] as List).cast<String>().toSet();
    final removedPages = (retired['removedPages'] as List)
        .cast<String>()
        .toSet();
    final retiredControls = (retired['controls'] as List)
        .cast<String>()
        .toSet();
    expect(
      catalog.pages.map((p) => p.id),
      containsAll(
        (coverage['baselinePages'] as List).where(
          (id) => !retiredPages.contains(id) && !removedPages.contains(id),
        ),
      ),
    );
    for (final id in retiredPages) {
      expect(catalog.page(id).id, 'display', reason: 'retired pages stay open');
    }
    final controls = catalog.pages
        .expand((p) => p.controls)
        .map((c) => c.id)
        .toSet();
    expect(
      controls,
      containsAll(
        (coverage['baselineControls'] as List).where(
          (id) => !retiredControls.contains(id),
        ),
      ),
    );
    expect(controls.intersection(retiredControls), isEmpty);
    expect(catalog.page('hypr-opengl').category, 'system');
    expect(catalog.page('hypr-render').category, 'system');
  });

  test('every added control has a pinned source and stays unavailable', () {
    final sources = {
      for (final source in coverage['sources'] as List)
        source['id'] as String: source as Map<String, dynamic>,
    };
    final addedPages = (coverage['addedPages'] as List).cast<String>().toSet();
    final addedControls = {
      for (final page in catalog.pages.where((p) => addedPages.contains(p.id)))
        for (final control in page.controls) control.id: control,
    };
    final evidence = (coverage['controls'] as List)
        .cast<Map<String, dynamic>>();
    expect(addedPages.length, 105);
    expect(evidence.length, 837);
    expect(
      evidence.map((e) => e['control']).toSet(),
      addedControls.keys.toSet(),
    );
    expect(evidence.where((e) => e['source'] == 'hypr-options').length, 368);
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
