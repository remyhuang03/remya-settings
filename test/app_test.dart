import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/app.dart';
import 'package:remya_settings/features/about/presentation/about_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_content.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';

void main() {
  late SettingsCatalog catalog;
  setUpAll(() {
    catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1280, 900),
  }) async {
    tester.view.resetPhysicalSize();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('application loads its bundled catalog', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const RemyaSettingsApp());
      await SettingsCatalog.load();
    });
    await tester.pumpAndSettle();
    expect(find.byType(SettingsShell), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browse, search, navigate back and open About and licenses', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, SettingsShell(catalog: catalog));
    expect(find.text('你的桌面，由你定义。'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('page-link-display')));
    await tester.pumpAndSettle();
    expect(find.text('显示器排列 · 示意图'), findsOneWidget);
    expect(
      tester
          .widgetList<Switch>(find.byType(Switch))
          .every((w) => w.onChanged == null),
      isTrue,
    );
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('你的桌面，由你定义。'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      '夜间模式',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-link-night-light')));
    await tester.pumpAndSettle();
    expect(find.text('强度'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    final licenseTile = find.text('第三方开源许可');
    await tester.ensureVisible(licenseTile);
    await tester.tap(licenseTile);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1280.0, 600.0, 360.0]) {
    testWidgets('all pages lay out with disabled controls at width $width', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 900);
      for (final page in catalog.pages) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const .all(20),
                  child: SettingsDetail(
                    key: ValueKey(page.id),
                    catalog: catalog,
                    page: page,
                    onPage: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(
          tester.takeException(),
          isNull,
          reason: 'Page ${page.id} at $width',
        );
        expect(
          tester
              .widgetList<Switch>(find.byType(Switch))
              .every((w) => w.onChanged == null),
          isTrue,
          reason: page.id,
        );
        expect(
          tester
              .widgetList<Slider>(find.byType(Slider))
              .every((w) => w.onChanged == null),
          isTrue,
          reason: page.id,
        );
        expect(
          tester
              .widgetList<TextField>(find.byType(TextField))
              .every((w) => w.enabled == false),
          isTrue,
          reason: page.id,
        );
      }
    });
  }

  testWidgets('Home and About remain usable at narrow width and large text', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: SettingsShell(catalog: catalog),
      ),
      size: const Size(360, 800),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('打开导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact navigation and reference controls remain accessible', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      SettingsShell(catalog: catalog),
      size: const Size(600, 720),
    );
    await tester.tap(find.byTooltip('打开导航'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-system')));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    await tester.tap(find.byKey(const ValueKey('page-link-display')));
    await tester.pumpAndSettle();
    final reference = find.text('Windows 参考细项');
    await tester.ensureVisible(reference);
    await tester.tap(reference);
    await tester.pumpAndSettle();
    expect(find.text('Ease cursor movement between displays'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
