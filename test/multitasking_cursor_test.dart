import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/multitasking/presentation/multitasking_page.dart';
import 'package:remya_settings/features/themes/presentation/cursor_page.dart';
import 'package:remya_settings/features/themes/presentation/themes_page.dart';
import 'package:remya_settings_client/settings_contract.dart';

import 'input_test.dart' show catalog, pump;
import 'display_test.dart' show fakeAppPreferencesController;

/// Answers `desktop` and `themes` like the service; `Set` updates options.
class FeaturesClient extends SettingsClient {
  FeaturesClient(this.features);
  final Map<String, Map<String, dynamic>> features;
  final calls = <List<String>>[];

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    if (method == 'Get' && arguments[0].startsWith('cursor-preview:')) {
      return {
        'sizes': [24, 32, 48],
        'images': <Object>[],
      };
    }
    final feature = method == 'Set'
        ? (arguments[0].startsWith('multitasking.') ||
                  !features['themes']!['options'].containsKey(arguments[0])
              ? 'desktop'
              : 'themes')
        : arguments[0];
    final state = features[feature]!;
    if (method == 'Set') {
      state['options'] = {
        ...state['options'] as Map,
        arguments[0]: jsonDecode(arguments[1]),
      };
    }
    return state;
  }
}

Map<String, dynamic> desktop([Map<String, Object?> options = const {}]) => {
  'options': {
    'multitasking.layout': 'dwindle',
    'multitasking.gaps-in': 5,
    'multitasking.gaps-out': [10, 20, 10, 20],
    'multitasking.border-size': 2,
    'multitasking.snap': false,
    'multitasking.resize-on-border': true,
    'cursor.inactive-timeout': 0.0,
    ...options,
  },
  'conflict': false,
  'conflicts': <String>[],
};

Map<String, dynamic> themes({List<Map<String, Object>> extra = const []}) => {
  'options': {
    'cursor.theme': 'Bibata',
    'cursor.size': 32,
    'themes.icon-theme': 'Papirus',
  },
  'conflict': false,
  'conflicts': <String>[],
  'cursor_themes': [
    {
      'id': 'Bibata',
      'name': 'Bibata',
      'user': false,
      'path': '/usr/share/icons/Bibata',
    },
    {
      'id': 'Mine',
      'name': 'My cursor',
      'user': true,
      'path': '/home/u/.local/share/icons/Mine',
    },
  ],
  'icon_themes': [
    {
      'id': 'Papirus',
      'name': 'Papirus',
      'user': false,
      'path': '/usr/share/icons/Papirus',
    },
    ...extra,
  ],
  'folders': [
    {
      'path': '/home/u/.local/share/icons',
      'user': true,
      'exists': false,
      'icons': true,
    },
    {'path': '/usr/share/icons', 'user': false, 'exists': true, 'icons': true},
    {'path': '/opt/missing', 'user': false, 'exists': false, 'icons': true},
  ],
  'user_folder': '/home/u/.local/share/icons',
};

void main() {
  testWidgets('layout thumbnails select a layout and dependent rows hide', (
    tester,
  ) async {
    final client = FeaturesClient({'desktop': desktop(), 'themes': themes()});
    await pump(
      tester,
      MultitaskingPage(
        catalog: catalog,
        page: catalog.page('multitasking'),
        client: client,
      ),
    );
    expect(find.byKey(const ValueKey('multitasking-preview')), findsOneWidget);
    expect(find.textContaining('Dwindle splits'), findsOneWidget);
    // Snap distances only matter while snapping is on.
    expect(
      find.byKey(const ValueKey('multitasking.snap-window-gap')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('multitasking.border-grab-area')),
      findsOneWidget,
    );
    // Different sides are shown rather than flattened.
    expect(
      find.textContaining('Top 10, right 20, bottom 10, left 20 px'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('layout-master')));
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Set', 'multitasking.layout', '"master"']);
    expect(
      find.textContaining('Master keeps one large window'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('multitasking.snap-switch')));
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Set', 'multitasking.snap', 'true']);
    expect(
      find.byKey(const ValueKey('multitasking.snap-window-gap')),
      findsOneWidget,
    );
  });

  testWidgets('cursor gallery, size stops, folders and removal', (
    tester,
  ) async {
    final client = FeaturesClient({'desktop': desktop(), 'themes': themes()});
    await pump(
      tester,
      CursorPage(
        catalog: catalog,
        page: catalog.page('cursor'),
        client: client,
        onPage: (_) {},
      ),
    );
    expect(find.text('Added by you'), findsOneWidget);
    expect(
      find.textContaining('This theme provides 24, 32, 48 px'),
      findsOneWidget,
    );
    // Missing system folders are left out; the user's folder is always shown.
    expect(find.text('/home/u/.local/share/icons'), findsOneWidget);
    expect(find.text('/opt/missing'), findsNothing);
    expect(find.text('Never'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('theme-Mine')));
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Set', 'cursor.theme', '"Mine"']);

    // The slider moves between the theme's own sizes.
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('cursor.size-slider')),
    );
    expect(slider.divisions, 2);
    slider.onChangeEnd!(2);
    await tester.pumpAndSettle();
    expect(
      client.calls.map((c) => c.join(' ')),
      contains('Set cursor.size 48'),
    );

    // The selected theme cannot be removed.
    await tester.tap(find.byKey(const ValueKey('cursor.remove-choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My cursor').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Choose another theme before removing this one.'),
      findsOneWidget,
    );
  });

  testWidgets('icon themes select through the service; removal hides', (
    tester,
  ) async {
    final client = FeaturesClient({
      'desktop': desktop(),
      'themes': themes(
        extra: [
          {
            'id': 'Tela',
            'name': 'Tela',
            'user': false,
            'path': '/usr/share/icons/Tela',
          },
        ],
      ),
    });
    // No pack is the user's own here.
    (client.features['themes']!['cursor_themes'] as List).removeLast();
    final preferences = fakeAppPreferencesController();
    addTearDown(preferences.dispose);
    await pump(
      tester,
      AppPreferencesScope(
        controller: preferences,
        child: ThemesPage(
          catalog: catalog,
          page: catalog.page('themes'),
          client: client,
          onPage: (_) {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('themes.icon-remove')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('theme-Tela')));
    await tester.pumpAndSettle();
    expect(client.calls.last, ['Set', 'themes.icon-theme', '"Tela"']);
    expect(
      find.byKey(const ValueKey('themes.icon-install-archive')),
      findsOneWidget,
    );
  });
}
