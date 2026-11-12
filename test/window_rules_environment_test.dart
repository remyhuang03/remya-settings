import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/environment/presentation/environment_page.dart';
import 'package:remya_settings/features/window_rules/presentation/window_rules_page.dart';
import 'package:remya_settings_client/settings_contract.dart';

import 'input_test.dart' show catalog, pump;

/// Answers `desktop` with saved window rules and variables; records writes.
class _Client extends SettingsClient {
  final sets = <(String, Map<String, dynamic>)>[];
  final state = <String, dynamic>{
    'options': <String, dynamic>{},
    'conflict': false,
    'conflicts': <String>[],
    'window_rules': [
      {
        'class': 'org.gnome.Nautilus',
        'float': true,
        'size': [60, 50],
        'workspace': '3',
        'silent': true,
      },
    ],
    'windows': [
      {'class': 'foot', 'title': 'Terminal'},
    ],
    'env': [
      {'name': 'GDK_BACKEND', 'value': 'wayland,x11'},
    ],
    'reserved_env': ['PATH', 'XCURSOR_SIZE'],
  };

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Set') {
      sets.add((arguments[0], jsonDecode(arguments[1])));
    }
    return state;
  }
}

void main() {
  testWidgets('window rules read as facts and the editor hides dependents', (
    tester,
  ) async {
    final client = _Client();
    await pump(
      tester,
      WindowRulesPage(
        catalog: catalog,
        page: catalog.page('window-rules'),
        client: client,
      ),
    );
    expect(
      find.text(
        'Floating, 60% × 50% of the display, '
        'Opens on Workspace 3 in the background',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('window-rules.remove')), findsNothing);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-rule-size-0')), findsOneWidget);
    // Turning floating off hides centering, size and pin and drops them on save.
    await tester.tap(find.byKey(const ValueKey('window-rule-float')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('window-rule-center')), findsNothing);
    expect(find.byKey(const ValueKey('window-rule-size-0')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('window-rule-save')));
    await tester.pumpAndSettle();
    final (id, value) = client.sets.single;
    expect(id, setWindowRuleId);
    expect(value['float'], false);
    expect(value['size'], isNull);
    expect(value['silent'], true);
    expect(value['previous'], {'class': 'org.gnome.Nautilus', 'title': ''});
  });

  testWidgets('variables refuse reserved names and suggestions fill both', (
    tester,
  ) async {
    final client = _Client();
    await pump(
      tester,
      EnvironmentPage(
        catalog: catalog,
        page: catalog.page('environment-variables'),
        client: client,
      ),
    );
    expect(find.text('GDK_BACKEND'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('environment-add')));
    await tester.pumpAndSettle();
    // A variable that is already set is not suggested again.
    expect(
      find.byKey(const ValueKey('environment-suggest-GDK_BACKEND')),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(const ValueKey('environment-name')),
      'XCURSOR_SIZE',
    );
    await tester.pump();
    expect(
      find.text('Managed by the session or another Settings page'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('environment-suggest-QT_QPA_PLATFORM')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('environment-save')));
    await tester.pumpAndSettle();
    expect(client.sets.single.$1, setEnvironmentVariableId);
    expect(client.sets.single.$2, {
      'name': 'QT_QPA_PLATFORM',
      'value': 'wayland;xcb',
      'previous': null,
    });
  });
}
