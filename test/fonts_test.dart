import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/fonts/application/fonts_controller.dart';
import 'package:remya_settings/features/fonts/presentation/fonts_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings_client/settings_contract.dart';

class _FakeDesktopClient extends SettingsClient {
  _FakeDesktopClient(this.state);
  Map<String, dynamic> state;
  final calls = <List<String>>[];

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> args = const [],
  ]) async {
    calls.add([method, ...args]);
    if (method == 'Set') {
      (state['options'] as Map)[args[0]] = jsonDecode(args[1]);
    }
    return state;
  }
}

void main() {
  testWidgets('previews wait for idle and follow repeated scroll jumps', (
    tester,
  ) async {
    final controller = FontsController(
      read: () async => {
        'families': [
          for (var i = 0; i < 100; i++) {'family': 'TestFont$i'},
        ],
      },
      write: (_, _) async => {},
    );
    addTearDown(controller.dispose);
    final catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox.expand(
            child: SingleChildScrollView(
              child: FontsPage(
                page: catalog.page('fonts'),
                controller: controller,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Iterable<Text> previews() => tester.widgetList<Text>(
      find.text('The quick brown fox jumps over the lazy dog'),
    );
    int loaded() =>
        previews().where((text) => text.style!.fontFamily != null).length;
    expect(loaded(), 0);
    expect(previews(), isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    expect(loaded(), greaterThan(0));
    expect(loaded(), lessThanOrEqualTo(8));
    final scroll = tester.widget<ListView>(find.byType(ListView)).controller!;
    for (var i = 20; i < 24; i++) {
      scroll.jumpTo(i * 76);
      await tester.pump(const Duration(milliseconds: 100));
      expect(loaded(), 0);
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(loaded(), greaterThan(0));
    expect(loaded(), lessThanOrEqualTo(8));
    final viewport = tester.getRect(find.byType(ListView));
    final cached = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'font-TestFont',
              ),
          skipOffstage: false,
        )
        .evaluate()
        .map((element) => element.widget.key!)
        .firstWhere(
          (key) =>
              tester.getTopLeft(find.byKey(key, skipOffstage: false)).dy >=
              viewport.bottom,
        );
    final row = find.byKey(cached, skipOffstage: false);
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          'The quick brown fox jumps over the lazy dog',
          skipOffstage: false,
        ),
      ),
      findsNothing,
    );
    tester.view.physicalSize = const Size(900, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(
        of: row,
        matching: find.text(
          'The quick brown fox jumps over the lazy dog',
          skipOffstage: false,
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'compositor font selects an installed family and shows conflicts',
    (tester) async {
      final controller = FontsController(
        read: () async => {
          'families': [
            {'family': 'Inter'},
            {'family': 'JetBrains Mono'},
          ],
        },
        write: (_, _) async => {},
      );
      addTearDown(controller.dispose);
      final client = _FakeDesktopClient({
        'options': {'fonts.compositor-family': 'Sans'},
        'system': {'fonts.compositor-family': 'Inter'},
        'saved': {'fonts.compositor-family': 'Sans'},
        'conflict': false,
        'conflicts': <String>[],
        'write_blocked': null,
        'error': null,
      });
      final catalog = SettingsCatalog.fromJson(
        jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FontsPage(
                page: catalog.page('fonts'),
                controller: controller,
                catalog: catalog,
                client: client,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(find.text('Compositor font family (font_family)'), findsOneWidget);
      final dropdown = find.byKey(
        const ValueKey('fonts.compositor-family-Sans-5'),
      );
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('JetBrains Mono').last);
      await tester.pumpAndSettle();
      expect(client.calls.last, [
        'Set',
        'fonts.compositor-family',
        '"JetBrains Mono"',
      ]);

      client.state = {
        ...client.state,
        'conflict': true,
        'conflicts': ['fonts.compositor-family'],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FontsPage(
                key: const ValueKey('fonts-conflict'),
                page: catalog.page('fonts'),
                controller: controller,
                catalog: catalog,
                client: client,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Compositor font family (font_family): system Inter, Settings Sans',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
