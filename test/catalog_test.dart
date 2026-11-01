import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/display/application/display_controller.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

Map<String, dynamic> readCatalog() =>
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('bundled catalog and application UI contain no Chinese text', () {
    final chinese = RegExp(r'[\u4e00-\u9fff]');
    expect(
      File('assets/settings/catalog.json').readAsStringSync(),
      isNot(matches(chinese)),
    );
    for (final file
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))) {
      expect(
        file.readAsStringSync(),
        isNot(matches(chinese)),
        reason: file.path,
      );
    }
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
      for (final page in catalog.pages) {
        expect(page.controls, isNotEmpty);
        expect(page.availability, isNot(SettingAvailability.available));
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
}
