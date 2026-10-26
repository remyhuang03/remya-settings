import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/about/presentation/about_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

Map<String, dynamic> readCatalog() =>
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    'every source route and backup leaf has a renderable catalog target',
    () {
      final catalog = SettingsCatalog.fromJson(readCatalog());
      final coverage = jsonDecode(
        File('docs/windows-settings-coverage.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(catalog.categories.length, greaterThanOrEqualTo(11));
      expect(catalog.pages.length, greaterThanOrEqualTo(202));
      expect(catalog.controlCount, greaterThanOrEqualTo(1321));
      expect(
        catalog.pages.expand((p) => p.controls).map((c) => c.kind).toSet(),
        SettingKind.values.toSet(),
      );
      expect((coverage['uris'] as List).length, 219);
      expect((coverage['backupSettings'] as List).length, 354);
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
          expect(control.availability, isNot(SettingAvailability.available));
          expect(control.reason, isNotEmpty);
        }
      }
      expect(catalog.search('夜间模式').map((p) => p.id), contains('night-light'));
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

  test(
    'About version matches the package version and icon source is retained',
    () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('version: $appVersion'),
      );
      expect(
        File('assets/icons/settings.svg').readAsStringSync(),
        contains('<svg'),
      );
      expect(File('assets/icons/settings.png').lengthSync(), greaterThan(0));
      expect(
        File('LICENSE').readAsStringSync(),
        contains('PolyForm Noncommercial License 1.0.0'),
      );
      expect(
        File('Cargo.toml').readAsStringSync(),
        contains('PolyForm-Noncommercial-1.0.0'),
      );
    },
  );
}
