import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/fonts/application/fonts_controller.dart';
import 'package:remya_settings/features/fonts/presentation/fonts_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

Map<String, dynamic> _family(String name, {int user = 0, int system = 1}) => {
  'family': name,
  'styles': ['Regular'],
  'formats': ['TrueType'],
  'files': ['/fonts/$name.ttf'],
  'user_files': user,
  'system_files': system,
};

void main() {
  final catalog = SettingsCatalog.fromJson(
    jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  Future<(FontsController, List<(String, String)>)> pump(
    WidgetTester tester,
    List<Map<String, dynamic>> families, {
    FontFilePicker? pick,
    Object? failure,
  }) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final writes = <(String, String)>[];
    final controller = FontsController(
      read: () async => {'families': families},
      write: (id, value) async {
        if (failure case final error?) throw error;
        writes.add((id, value));
        return {};
      },
    );
    await controller.reload();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              FontsPage(
                page: catalog.page('fonts'),
                controller: controller,
                pickFiles: pick ?? () async => const [],
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (controller, writes);
  }

  testWidgets('rows build lazily and search filters by name', (tester) async {
    final (controller, _) = await pump(tester, [
      for (var i = 0; i < 400; i++) _family('Family $i'),
      _family('Noto Sans'),
    ]);
    expect(find.text('401 font families'), findsOneWidget);
    // Previews load whole font files, so only rows near the viewport may exist.
    final built = find.textContaining('The quick brown').evaluate().length;
    expect(built, inInclusiveRange(1, 20));
    await tester.scrollUntilVisible(
      find.text('Noto Sans'),
      2000,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Noto Sans'), findsOneWidget);
    expect(find.text('Family 0'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 40000));
    await tester.pumpAndSettle();

    var rebuilt = 0;
    controller.addListener(() => rebuilt++);
    await controller.reload();
    expect(rebuilt, 0, reason: 'an unchanged list must not rebuild the page');

    await tester.enterText(find.byKey(const ValueKey('fonts-search')), 'noto');
    await tester.pumpAndSettle();
    expect(find.text('1 font families'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('fonts-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No fonts found'), findsOneWidget);
  });

  testWidgets('system fonts offer no uninstall action', (tester) async {
    await pump(tester, [_family('Noto Sans')]);
    await tester.tap(find.text('Noto Sans'));
    await tester.pumpAndSettle();
    expect(find.text('Installed for the whole system'), findsOneWidget);
    expect(find.byKey(const ValueKey('fonts-uninstall')), findsNothing);
    expect(find.text('Regular'), findsOneWidget);
  });

  testWidgets('uninstall asks first and uses the family name', (tester) async {
    final (_, writes) = await pump(tester, [
      _family('Mine', user: 1, system: 0),
    ]);
    await tester.tap(find.text('Mine'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('fonts-uninstall')));
    await tester.pumpAndSettle();
    expect(writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('fonts-uninstall-confirm')));
    await tester.pumpAndSettle();
    expect(writes.single, (fontsUninstallSettingId, 'Mine'));
  });

  testWidgets('install sends every chosen file and failures stay visible', (
    tester,
  ) async {
    final (_, writes) = await pump(tester, [
      _family('Noto Sans'),
    ], pick: () async => ['/a.ttf', '/b.otf']);
    await tester.tap(find.byKey(const ValueKey('fonts-install')));
    await tester.pumpAndSettle();
    expect(writes.map((w) => w.$2), ['/a.ttf', '/b.otf']);

    await pump(
      tester,
      [_family('Noto Sans')],
      pick: () async => ['/bad.ttf'],
      failure: StateError('This file is not a valid font'),
    );
    await tester.tap(find.byKey(const ValueKey('fonts-install')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('fonts-error')), findsOneWidget);
  });
}
