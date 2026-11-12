import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/about/presentation/about_page.dart';
import 'package:remya_settings/features/input/presentation/keyboard_shortcuts_page.dart';
import 'package:remya_settings/features/input/presentation/mouse_page.dart';
import 'package:remya_settings/features/input/presentation/touchpad_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings_client/settings_contract.dart';

final catalog = SettingsCatalog.fromJson(
  jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
      as Map<String, dynamic>,
);

Map<String, dynamic> inputState({
  Map<String, Object?> options = const {},
  List<String> conflicts = const [],
}) => {
  'options': {
    'mouse.primary-button': false,
    'mouse.pointer-speed': 0.0,
    'mouse.acceleration': '',
    'mouse.natural-scroll': false,
    'mouse.focus-follows': 1,
    'mouse.refocus': true,
    'touchpad.tap-to-click': true,
    'touchpad.tap-and-drag': true,
    'touchpad.click-method': false,
    ...options,
  },
  'system': {'mouse.pointer-speed': 0.5},
  'saved': {'mouse.pointer-speed': 0.0},
  'conflict': conflicts.isNotEmpty,
  'conflicts': conflicts,
  'mice': ['usb-mouse'],
  'touchpads': <String>[],
  'key_labels': {'24': 'Q', '25': 'W'},
  'custom': [
    {
      'keys': 'SUPER + Return',
      'modifiers': ['SUPER'],
      'label': 'Enter',
      'action': 'command',
      'command': 'foot',
      'description': 'Terminal',
    },
  ],
  'disabled': <Object>[],
  'shortcuts': [
    {
      'keys': 'SUPER + q',
      'modifiers': ['SUPER'],
      'key': 'q',
      'label': 'Q',
      'code': 24,
      'submap': '',
      'description': 'Window: Close',
      'actions': ['Close window'],
      'custom': false,
    },
    {
      'keys': 'SUPER + SHIFT + w',
      'modifiers': ['SUPER', 'SHIFT'],
      'key': 'w',
      'label': 'W',
      'code': 25,
      'submap': '',
      'description': '',
      'actions': ['Run a command'],
      'custom': false,
    },
  ],
  'write_blocked': null,
  'error': null,
};

class FakeClient extends SettingsClient {
  FakeClient(this.state);
  Map<String, dynamic> state;
  final calls = <List<String>>[];

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    if (method == 'Set') {
      final options = {
        ...state['options'] as Map,
        arguments[0]: jsonDecode(arguments[1]),
      };
      state = {...state, 'options': options};
    }
    if (method == 'Resolve') {
      state = {...state, 'conflict': false, 'conflicts': <String>[]};
    }
    return state;
  }
}

Future<void> pump(WidgetTester tester, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: page)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mouse buttons map to left-handed and dependent rows hide', (
    tester,
  ) async {
    final client = FakeClient(inputState());
    await pump(
      tester,
      MousePage(catalog: catalog, page: catalog.page('mouse'), client: client),
    );
    expect(find.byKey(const ValueKey('mouse-diagram')), findsOneWidget);
    expect(find.text('usb-mouse'), findsOneWidget);
    expect(find.text('Device default until you choose'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mouse.refocus')),
      findsNothing,
      reason: 'Advanced is collapsed',
    );

    await tester.tap(find.text('Right'));
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Set', 'mouse.primary-button', 'true']);
    expect(find.textContaining('Right button selects'), findsOneWidget);

    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mouse.refocus')), findsOneWidget);
    client.state = inputState(options: {'mouse.focus-follows': 2});
    await tester.tap(find.text('Middle-click paste'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: MousePage(
              key: const ValueKey('again'),
              catalog: catalog,
              page: catalog.page('mouse'),
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mouse.refocus')), findsNothing);
  });

  testWidgets('tap options disappear with tap-to-click and conflicts resolve', (
    tester,
  ) async {
    final client = FakeClient(
      inputState(
        options: {'touchpad.tap-to-click': false},
        conflicts: ['mouse.pointer-speed'],
      ),
    );
    await pump(
      tester,
      TouchpadPage(
        catalog: catalog,
        page: catalog.page('touchpad'),
        client: client,
      ),
    );
    expect(find.byKey(const ValueKey('touchpad.tap-and-drag')), findsNothing);
    expect(find.byKey(const ValueKey('touchpad.tap-buttons')), findsNothing);
    expect(find.textContaining('No touchpad is connected'), findsOneWidget);
    expect(
      find.text('Pointer speed: system +50%, Settings Default'),
      findsOneWidget,
    );
    // Writes stay disabled until the conflict is resolved.
    final tap = tester.widget<Switch>(
      find.byKey(const ValueKey('touchpad.tap-to-click-switch')),
    );
    expect(tap.onChanged, isNull);

    await tester.tap(find.text('Use system configuration'));
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Resolve', 'input', 'system']);
    await tester.tap(
      find.byKey(const ValueKey('touchpad.tap-to-click-switch')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('touchpad.tap-and-drag')), findsOneWidget);
  });

  testWidgets('the keyboard map filters by modifiers and lists shortcuts', (
    tester,
  ) async {
    final client = FakeClient(inputState());
    await pump(
      tester,
      KeyboardShortcutsPage(
        catalog: catalog,
        page: catalog.page('keyboard-shortcuts'),
        client: client,
      ),
    );
    Color keyColor(int code) => tester
        .widget<Material>(
          find
              .ancestor(
                of: find.byKey(ValueKey('keyboard-key-$code')),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;
    final scheme = Theme.of(
      tester.element(find.byKey(const ValueKey('keyboard-key-24'))),
    ).colorScheme;
    expect(keyColor(24), scheme.primaryContainer);
    expect(keyColor(25), scheme.surfaceContainerHigh);

    await tester.tap(find.byKey(const ValueKey('keyboard-key-50')));
    await tester.pumpAndSettle();
    expect(keyColor(25), scheme.primaryContainer);
    expect(keyColor(24), scheme.surfaceContainerHigh);

    await tester.tap(find.byKey(const ValueKey('keyboard-key-25')));
    await tester.pumpAndSettle();
    expect(find.text('Run a command'), findsWidgets);

    expect(find.text('Terminal'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('shortcut-search')),
      'close',
    );
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Window'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn off'));
    await tester.pumpAndSettle();
    expect(client.calls.last, [
      'Set',
      disableShortcutId,
      jsonEncode({'keys': 'SUPER + q', 'disabled': true}),
    ]);
  });

  testWidgets('the About coverage parts add up to the total', (tester) async {
    await pump(tester, AboutPage(catalog: catalog, onLicenses: () {}));
    final controls = catalog.pages.expand((p) => p.controls).toList();
    int count(String label) => int.parse(
      tester.widget<Text>(find.byKey(ValueKey('coverage-$label'))).data!,
    );
    expect(
      count('Supported') + count('Not yet done'),
      count('Total'),
    );
    expect(count('Total'), controls.length);
    expect(find.byKey(const ValueKey('coverage-progress')), findsOneWidget);
  });
}
