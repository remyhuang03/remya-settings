import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/language/presentation/language_page.dart';
import 'package:remya_settings_client/settings_contract.dart';

import 'input_test.dart' show catalog, pump;

const _categories = [
  'LC_MEASUREMENT',
  'LC_MONETARY',
  'LC_NUMERIC',
  'LC_PAPER',
  'LC_TIME',
];

/// Answers `language`, `input`, the locale and layout lists and previews.
class _Client extends SettingsClient {
  _Client({this.conflict = false});
  final bool conflict;
  final calls = <List<String>>[];
  String language = 'en_US.UTF-8';
  String format = '';
  List<Object?> layouts = [
    {'layout': 'us', 'variant': ''},
    {'layout': 'de', 'variant': 'nodeadkeys'},
  ];
  String options = 'caps:escape';

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  Map<String, dynamic> _language() => {
    'options': {displayLanguageId: language, regionalFormatId: format},
    'formats': {for (final c in _categories) c: format},
    'saved': {displayLanguageId: language, regionalFormatId: format},
    'system': {
      displayLanguageId: conflict ? 'de_DE.UTF-8' : language,
      regionalFormatId: format,
    },
    'conflict': conflict,
    'conflicts': [if (conflict) displayLanguageId],
  };

  Map<String, dynamic> _input() => {
    'options': {keyboardLayoutsId: layouts, keyboardOptionsId: options},
    'conflict': false,
    'conflicts': <String>[],
  };

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    final key = arguments.isEmpty ? '' : arguments[0];
    if (method == 'Set') {
      final value = jsonDecode(arguments[1]);
      switch (key) {
        case displayLanguageId:
          language = value as String;
        case regionalFormatId:
          format = value as String;
        case keyboardLayoutsId:
          layouts = value as List;
        case keyboardOptionsId:
          options = value as String;
      }
      return key.startsWith('language.keyboard') ? _input() : _language();
    }
    if (key.startsWith('format-preview:')) {
      return {
        'date': key.endsWith('de_DE.UTF-8') ? '14.03.2026' : '03/14/2026',
        'time': '15:09:00',
        'weekday': 'Saturday',
        'number': '1,234,567.89',
        'currency': r'$1,234.56',
        'measurement': 'US customary',
        'paper': 'US Letter',
      };
    }
    return switch (key) {
      'language' => _language(),
      'input' => _input(),
      'locales' => {
        'options': [
          {'id': 'de_DE.UTF-8', 'label': 'German (Germany)'},
          {'id': 'en_US.UTF-8', 'label': 'American English (United States)'},
        ],
      },
      'keyboard-layouts' => {
        'layouts': [
          {'id': 'us', 'label': 'English (US)', 'variants': <Object>[]},
          {
            'id': 'de',
            'label': 'German',
            'variants': [
              {'id': 'nodeadkeys', 'label': 'German (no dead keys)'},
            ],
          },
          {'id': 'fr', 'label': 'French', 'variants': <Object>[]},
        ],
      },
      _ => throw StateError('unexpected $method $arguments'),
    };
  }
}

Future<void> _pump(WidgetTester tester, _Client client) => pump(
  tester,
  LanguagePage(
    catalog: catalog,
    page: catalog.page('language'),
    client: client,
    environment: const {'LANG': 'en_US.UTF-8'},
  ),
);

Future<void> _pick(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(ValueKey('picker-$id')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'language and format use readable names, preview and sign-in hint',
    (tester) async {
      final client = _Client();
      await _pump(tester, client);
      expect(find.text('American English (United States)'), findsOneWidget);
      expect(find.text('Same as display language'), findsOneWidget);
      expect(find.text('03/14/2026'), findsOneWidget);
      expect(find.textContaining('/etc/locale.gen'), findsOneWidget);
      expect(find.text('Sign out and back in to apply'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('language.format-choose')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('picker-search')),
        'germ',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('picker-en_US.UTF-8')), findsNothing);
      await _pick(tester, 'de_DE.UTF-8');
      expect(
        client.calls,
        contains(equals(['Set', regionalFormatId, '"de_DE.UTF-8"'])),
      );
      expect(find.text('14.03.2026'), findsOneWidget);
      // This session still uses the formats it started with.
      expect(find.text('Sign out and back in to apply'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('language.display-choose')));
      await tester.pumpAndSettle();
      await _pick(tester, 'de_DE.UTF-8');
      expect(
        client.calls,
        contains(equals(['Set', displayLanguageId, '"de_DE.UTF-8"'])),
      );
    },
  );

  testWidgets(
    'layouts reorder, remove and add; the switch keeps other options',
    (tester) async {
      final client = _Client();
      await _pump(tester, client);
      expect(find.text('German (no dead keys)'), findsOneWidget);
      expect(find.text('Default'), findsOneWidget);

      await tester.tap(find.byTooltip('Move up').last);
      await tester.pumpAndSettle();
      expect(client.layouts.first, {'layout': 'de', 'variant': 'nodeadkeys'});

      await tester.tap(find.byKey(const ValueKey('add-keyboard-layout')));
      await tester.pumpAndSettle();
      // Layouts already in the list are not offered again.
      expect(find.byKey(const ValueKey('picker-us()')), findsNothing);
      await _pick(tester, 'fr()');
      expect(client.layouts.last, {'layout': 'fr', 'variant': ''});

      await tester.tap(find.byType(DropdownMenu<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alt+Shift').last);
      await tester.pumpAndSettle();
      expect(client.options, 'caps:escape,grp:alt_shift_toggle');

      // With one layout left, the switching shortcut has nothing to do.
      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Remove').first);
        await tester.pumpAndSettle();
      }
      expect(client.layouts, [
        {'layout': 'fr', 'variant': ''},
      ]);
      expect(find.byKey(const ValueKey(keyboardOptionsId)), findsNothing);
      final remove = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.delete_outline_rounded),
          matching: find.byType(IconButton),
        ),
      );
      expect(remove.onPressed, isNull);
    },
  );

  testWidgets('a conflict offers both resolutions and blocks changes', (
    tester,
  ) async {
    final client = _Client(conflict: true);
    await _pump(tester, client);
    expect(
      find.text('Language settings differ from saved Settings'),
      findsOneWidget,
    );
    expect(
      find.textContaining('system de_DE.UTF-8, Settings en_US.UTF-8'),
      findsOneWidget,
    );
    final choose = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('language.display-choose')),
    );
    expect(choose.onPressed, isNull);
    await tester.tap(find.text('Apply Settings configuration'));
    await tester.pumpAndSettle();
    expect(client.calls, contains(equals(['Resolve', 'language', 'settings'])));
  });
}
