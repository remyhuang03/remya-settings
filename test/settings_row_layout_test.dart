import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/settings/presentation/settings_widgets.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/appearance/domain/app_preferences.dart';
import 'package:remya_settings/features/integration/service_controllers.dart';
import 'package:remya_settings_client/settings_contract.dart';

class _BackgroundAccentClient extends SettingsClient {
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async => switch (arguments.single) {
    'accent' => {'source': 'background', 'color': '#8855AA', 'error': null},
    'theme' => {
      'version': 1,
      'theme': {'theme_mode': 'light', 'style_variant': 'tonal_spot'},
    },
    'system' => {'mode': 'light', 'targets': <Map>[]},
    _ => throw StateError('Unexpected appearance request'),
  };
}

void main() {
  Future<void> host(
    WidgetTester tester,
    double width,
    Widget? control, {
    Widget label = const Text('Label'),
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: .topLeft,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: SettingRow(id: 'row', label: label, control: control),
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'the Themes background accent readout stays against the surface left inset',
    (tester) async {
      final client = _BackgroundAccentClient();
      final preferences = ServicePreferencesController(client);
      addTearDown(client.close);
      addTearDown(preferences.dispose);
      final catalog = SettingsCatalog.fromJson(
        jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final accent = catalog
          .page('themes')
          .controls
          .firstWhere((s) => s.id == accentColorSettingId);
      await preferences.reload();
      final navigation = ValueNotifier<String?>('themes');
      addTearDown(navigation.dispose);
      addTearDown(tester.view.reset);
      for (final width in [1280.0, 640.0]) {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          AppPreferencesScope(
            controller: preferences,
            child: MaterialApp(
              home: SettingsShell(catalog: catalog, navigation: navigation),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey(accentColorSettingId));
        await tester.ensureVisible(row);
        final title = find.descendant(
          of: row,
          matching: find.text(accent.title),
        );
        final hex = find.byKey(const ValueKey('accent-readout'));
        final surface = find
            .ancestor(of: row, matching: find.byType(SettingsSurface))
            .first;
        expect(tester.getSize(row).width, tester.getSize(surface).width);
        expect(
          tester.getTopLeft(title).dx,
          closeTo(tester.getTopLeft(surface).dx + 20, .1),
        );
        expect(tester.getTopLeft(hex).dx, tester.getTopLeft(title).dx);
        expect(
          find.descendant(of: row, matching: find.byType(FilledButton)),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('wrapped controls use actual width below former breakpoints', (
    tester,
  ) async {
    for (final control in <Widget>[
      Padding(
        padding: const .all(4),
        child: Switch(value: false, onChanged: (_) {}),
      ),
      Semantics(
        label: 'Choice',
        child: DropdownMenu<String>(
          width: 140,
          initialSelection: 'One',
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: 'One', label: 'One'),
          ],
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilledButton(onPressed: () {}, child: const Text('First')),
          FilledButton(onPressed: () {}, child: const Text('Second')),
        ],
      ),
    ]) {
      await host(tester, 400, control);
      final label = tester.getRect(find.text('Label'));
      final rect = tester.getRect(find.byWidget(control));
      expect(
        (label.center.dy - rect.center.dy).abs(),
        lessThan(1),
        reason: '$label vs $rect',
      );
      expect(rect.right, 380);
      expect(rect.left, greaterThan(label.right));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'readouts and label-only rows retain natural height and alignment',
    (tester) async {
      await host(
        tester,
        400,
        const SelectableText('6.0'),
        label: const Column(
          crossAxisAlignment: .start,
          children: [Text('Version'), Text('Read only')],
        ),
      );
      expect(tester.getSize(find.byType(SettingRow)).height, lessThan(140));
      expect(
        tester.getCenter(find.byType(SelectableText)).dy,
        closeTo(tester.getCenter(find.byType(Column)).dy, 1),
      );
      await host(
        tester,
        220,
        null,
        label: const Column(
          crossAxisAlignment: .start,
          children: [Text('Account'), SelectableText('Local account')],
        ),
      );
      expect(tester.getTopLeft(find.text('Account')).dx, 20);
      expect(tester.getTopLeft(find.byType(SelectableText)).dx, 20);
      expect(tester.getSize(find.byType(SettingRow)).height, lessThan(140));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('page links keep badges on the right whenever the groups fit', (
    tester,
  ) async {
    const page = SettingsPageSpec(
      id: 'preview',
      category: 'system',
      title: 'Page',
      description: 'Details',
      preview: 'none',
      availability: .planned,
      reason: 'Not implemented',
      windowsUris: [],
      children: [],
      sections: [],
    );
    var opened = 0;
    for (final width in [400.0, 220.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: .topLeft,
              child: SizedBox(
                width: width,
                child: PageLink(
                  page: page,
                  icon: Icons.settings_outlined,
                  onTap: () => opened++,
                ),
              ),
            ),
          ),
        ),
      );
      final badge = tester.getRect(find.byType(AvailabilityBadge));
      final title = tester.getRect(find.text('Page'));
      final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
      expect(chevron.right, width - 20);
      expect(chevron.center.dy, badge.center.dy);
      if (width == 400) {
        expect(
          badge.center.dy,
          closeTo(
            (title.top + tester.getBottomLeft(find.text('Details')).dy) / 2,
            1,
          ),
        );
      } else {
        expect(
          badge.top,
          greaterThan(tester.getBottomLeft(find.text('Details')).dy),
        );
      }
      await tester.tap(find.text('Page'));
      expect(tester.takeException(), isNull);
    }
    expect(opened, 2);
  });

  testWidgets('only insufficient natural width stacks and right actions wrap', (
    tester,
  ) async {
    final control = Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: .end,
      children: [
        FilledButton(onPressed: () {}, child: const Text('First action')),
        FilledButton(onPressed: () {}, child: const Text('Second action')),
      ],
    );
    await host(tester, 220, control);
    final rect = tester.getRect(find.byWidget(control));
    expect(rect.top, greaterThan(tester.getBottomLeft(find.text('Label')).dy));
    expect(rect.right, 200);
    expect(
      tester.getTopLeft(find.text('Second action')).dy,
      greaterThan(tester.getBottomLeft(find.text('First action')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'moving between a row and stacked layout preserves input focus and draft',
    (tester) async {
      final focus = FocusNode();
      final text = TextEditingController();
      addTearDown(focus.dispose);
      addTearDown(text.dispose);
      Widget input() => SizedBox(
        width: 180,
        child: TextField(focusNode: focus, controller: text),
      );
      await host(tester, 400, input());
      await tester.enterText(find.byType(TextField), 'draft');
      expect(focus.hasFocus, isTrue);
      final field = tester.state(find.byType(TextField));
      await host(tester, 220, input());
      await tester.pump();
      expect(tester.state(find.byType(TextField)), same(field));
      expect(focus.hasFocus, isTrue);
      expect(text.text, 'draft');
      await host(tester, 400, input());
      expect(focus.hasFocus, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
