import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/app.dart';
import 'package:remya_settings/features/about/presentation/about_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_content.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/settings/presentation/settings_title_bar.dart';
import 'package:remya_settings/features/settings/presentation/settings_widgets.dart';

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
    expect(find.byType(SettingsTitleBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('title bar requests native close, drag and maximize', (
    tester,
  ) async {
    final calls = <String>[];
    const channel = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'isMaximized' ? false : null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await mount(tester, const SettingsTitleBar());
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(calls, contains('close'));
    await tester.drag(find.byType(DragToMoveArea), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(calls, contains('startDragging'));
    await tester.tap(find.byType(DragToMoveArea));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(DragToMoveArea));
    await tester.pumpAndSettle();
    expect(calls, contains('maximize'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar categories collapse and show icons on secondary pages', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, SettingsShell(catalog: catalog));
    expect(find.byType(PageLink), findsNothing);
    expect(find.text('Hyprland · UI Preview'), findsNothing);
    final category = find.byKey(const ValueKey('nav-system'));
    final display = find.byKey(const ValueKey('nav-page-display'));
    expect(display, findsNothing);
    await tester.tap(category);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(display).leading, isA<Icon>());
    await tester.tap(category);
    await tester.pumpAndSettle();
    expect(display, findsNothing);
    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(display);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(display).selected, isTrue);
    expect(find.text('Display arrangement · Preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'About uses dated version and repository list item without status labels',
    (tester) async {
      await mount(tester, const AboutPage());
      expect(find.text('v$appVersion'), findsOneWidget);
      final repository = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Repository'),
          matching: find.byType(ListTile),
        ),
      );
      expect(repository.onTap, isNotNull);
      expect(repository.trailing, isA<Icon>());
      expect(find.text('Available'), findsNothing);
      expect(find.text('Project status'), findsNothing);
      expect(find.text('Global system settings for Hyprland'), findsNothing);
      expect(
        find.text(
          'Windows Settings organization with Material Design 3 Expressive styling.',
        ),
        findsNothing,
      );
      await mount(tester, const AvailabilityBadge(.available));
      expect(find.byType(Tooltip), findsNothing);
      expect(find.byType(Icon), findsNothing);
      expect(find.text('Available'), findsNothing);
    },
  );

  testWidgets('browse, search, navigate back and open About and licenses', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, SettingsShell(catalog: catalog));
    expect(find.text('Your desktop, your way.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-system')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-page-display')));
    await tester.pumpAndSettle();
    expect(find.text('Display arrangement · Preview'), findsOneWidget);
    expect(
      tester
          .widgetList<Switch>(find.byType(Switch))
          .every((w) => w.onChanged == null),
      isTrue,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Your desktop, your way.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'Night light',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-link-night-light')));
    await tester.pumpAndSettle();
    expect(find.text('Strength'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    final licenseTile = find.text('Third-party licenses');
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
    await tester.tap(find.byTooltip('Open navigation'));
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
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-system')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-page-display')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-page-display')));
    await tester.pumpAndSettle();
    final reference = find.text('Windows reference settings');
    await tester.ensureVisible(reference);
    await tester.tap(reference);
    await tester.pumpAndSettle();
    expect(find.text('Ease cursor movement between displays'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
