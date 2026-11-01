import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/appearance/data/app_preferences_file.dart';
import 'package:remya_settings/features/about/presentation/about_page.dart';
import 'package:remya_settings/features/about/presentation/licenses_view.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_content.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/settings/presentation/settings_title_bar.dart';
import 'package:remya_settings/features/settings/presentation/settings_widgets.dart';

import 'support/fake_system_appearance.dart';

void main() {
  late SettingsCatalog catalog;
  setUpAll(() {
    catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });

  late AppPreferencesController preferences;
  setUp(() {
    final directory = Directory.systemTemp.createTempSync(
      'remya-settings-widgets-',
    );
    preferences = AppPreferencesController(
      systemAppearance: FakeSystemAppearance(),
      store: AppPreferencesFile(File('${directory.path}/config.toml')),
    );
    addTearDown(() {
      preferences.dispose();
      directory.deleteSync(recursive: true);
    });
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
        home: AppPreferencesScope(
          controller: preferences,
          child: Scaffold(body: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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

  for (final width in [1280.0, 600.0, 360.0]) {
    testWidgets('persistent single-level navigation at $width', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(
        tester,
        SettingsShell(catalog: catalog),
        size: Size(width, 900),
      );
      final category = find.byKey(const ValueKey('nav-system'));
      await tester.tap(category);
      await tester.pumpAndSettle();
      final display = find.byKey(const ValueKey('nav-page-display'));
      expect(tester.widget(display), isA<FilledButton>());
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Display arrangement · Preview'), findsOneWidget);
      expect(
        width < 1000
            ? tester.widget(category) is IconButton
            : tester.widget(category) is ListTile,
        isTrue,
      );
      await tester.tap(category);
      await tester.pumpAndSettle();
      expect(display, findsOneWidget);
      if (width < 1000) {
        await tester.tap(find.byTooltip('Find a setting'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('settings-search')),
          'Night light',
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('page-link-night-light')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [1280.0, 600.0, 360.0]) {
    testWidgets('page buttons wrap with leading icons at $width', (
      tester,
    ) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final navigation = ValueNotifier<String?>('date-time');
      addTearDown(navigation.dispose);
      await mount(
        tester,
        SettingsShell(catalog: catalog, navigation: navigation),
        size: Size(width, 900),
      );
      final group = find.byKey(const ValueKey('page-buttons-time'));
      expect(tester.widget(group), isA<Wrap>());
      final pages = catalog.inCategory('time');
      final first = find.byKey(ValueKey('nav-page-${pages.first.id}'));
      final last = find.byKey(ValueKey('nav-page-${pages.last.id}'));
      expect(
        tester.getTopLeft(last).dy,
        greaterThan(tester.getTopLeft(first).dy),
      );
      final bounds = tester.getRect(group);
      for (final page in pages) {
        final button = find.byKey(ValueKey('nav-page-${page.id}'));
        expect(
          find.descendant(
            of: button,
            matching: find.byIcon(pageIcon(page, catalog.category('time'))),
          ),
          findsOneWidget,
        );
        final rectangle = tester.getRect(button);
        expect(rectangle.left, greaterThanOrEqualTo(bounds.left));
        expect(rectangle.right, lessThanOrEqualTo(bounds.right + 0.01));
      }
      expect(
        pageIcon(pages.first, catalog.category('time')),
        Icons.schedule_rounded,
      );
      expect(
        pageIcon(catalog.page('language'), catalog.category('time')),
        Icons.translate_rounded,
      );
      await tester.ensureVisible(last);
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SettingsDetail>(find.byType(SettingsDetail)).page.id,
        pages.last.id,
      );
      await tester.ensureVisible(find.byType(SettingsDetail));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'compact selected icons use the container foreground in ${brightness.name}',
      (tester) async {
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final theme = preferences.preferences.theme(brightness);
        final navigation = ValueNotifier<String?>('date-time');
        addTearDown(navigation.dispose);
        await mount(
          tester,
          Theme(
            data: theme,
            child: SettingsShell(catalog: catalog, navigation: navigation),
          ),
          size: const Size(600, 900),
        );
        final selected = find.byKey(const ValueKey('nav-time'));
        final icon = find.descendant(of: selected, matching: find.byType(Icon));
        expect(
          IconTheme.of(tester.element(icon)).color,
          theme.colorScheme.onSecondaryContainer,
        );
        final button = tester.widget<IconButton>(selected);
        expect(
          button.style!.backgroundColor!.resolve({WidgetState.selected}),
          theme.colorScheme.secondaryContainer,
        );
        final luminances = [
          theme.colorScheme.onSecondaryContainer.computeLuminance(),
          theme.colorScheme.secondaryContainer.computeLuminance(),
        ]..sort();
        expect(
          (luminances.last + 0.05) / (luminances.first + 0.05),
          greaterThanOrEqualTo(3),
        );
        await tester.tap(find.byKey(const ValueKey('nav-home')));
        await tester.pumpAndSettle();
        expect(
          IconTheme.of(tester.element(icon)).color,
          theme.colorScheme.onSurfaceVariant,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('About shows live catalog coverage and repository information', (
    tester,
  ) async {
    await mount(tester, AboutPage(catalog: catalog, onLicenses: () {}));
    expect(find.text('v$appVersion'), findsOneWidget);
    final controls = catalog.pages.expand((page) => page.controls);
    for (final stat in [
      (
        'Supported',
        controls.where((item) => item.availability == .available).length,
      ),
      (
        'Not yet done',
        controls.where((item) => item.availability == .planned).length,
      ),
      ('Total', catalog.controlCount),
    ]) {
      expect(
        tester.widget<Text>(find.byKey(ValueKey('coverage-${stat.$1}'))).data,
        '${stat.$2}',
      );
    }

    expect(
      find.ancestor(of: find.text('v$appVersion'), matching: find.byType(Chip)),
      findsNothing,
    );
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
  });

  testWidgets('browse, search, navigate back and open About and licenses', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, SettingsShell(catalog: catalog));
    expect(find.text('Your desktop, your way.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('nav-system')));
    await tester.pumpAndSettle();
    expect(find.text('Display arrangement · Preview'), findsOneWidget);
    expect(
      tester
          .widgetList<Switch>(find.byType(Switch))
          .every((w) => w.onChanged == null),
      isTrue,
    );
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text('System'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('settings-search')));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
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
    expect(find.byType(LicensesView), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-about')), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [1280.0, 600.0, 360.0]) {
    testWidgets('preview controls stay disabled at detail width $width', (
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
            home: AppPreferencesScope(
              controller: preferences,
              child: Scaffold(
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

  testWidgets('Home and About remain usable at minimum size and large text', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: Column(
          children: [
            const SettingsTitleBar(),
            Expanded(child: SettingsShell(catalog: catalog)),
          ],
        ),
      ),
      size: const Size(1000, 600),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(Drawer), findsNothing);
    expect(find.byTooltip('Open navigation'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('nav-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'persistent sidebar remains accessible without Display Windows references',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(
        tester,
        SettingsShell(catalog: catalog),
        size: const Size(1000, 720),
      );
      expect(find.byType(Drawer), findsNothing);
      expect(find.byTooltip('Open navigation'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('nav-system')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('nav-page-display')), findsOneWidget);
      expect(find.text('Windows reference settings'), findsNothing);
      expect(
        catalog.page('display').sections.map((section) => section.title),
        isNot(contains('Windows reference settings')),
      );
      expect(find.text('Ease cursor movement between displays'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
