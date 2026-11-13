import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/workspaces/presentation/workspaces_page.dart';
import 'package:remya_client/settings_contract.dart';

import 'input_test.dart' show catalog, pump;

/// Answers `desktop` like the service: rule writes replace or drop a rule.
class _Client extends SettingsClient {
  final calls = <List<String>>[];
  final state = <String, dynamic>{
    'options': {
      'workspaces.initial-workspace-tracking': 0,
      'workspaces.close-special-on-empty': true,
      'workspaces.hide-special-on-change': true,
      'workspaces.center-on': 1,
      'workspaces.special-fallthrough': false,
    },
    'conflict': false,
    'conflicts': <String>[],
    'rules': [
      {'workspace': '2', 'monitor': 'DP-1', 'persistent': true},
    ],
    'live_rules': [
      {
        'workspace': '2',
        'monitor': 'DP-1',
        'persistent': true,
        'settings': true,
      },
      {'workspace': '9', 'monitor': 'HDMI-A-1', 'settings': false},
    ],
    'monitors': [
      {
        'name': 'DP-1',
        'x': 0,
        'y': 0,
        'width': 1920,
        'height': 1080,
        'active_workspace': '1',
        'special_workspace': '',
      },
      {
        'name': 'HDMI-A-1',
        'x': 1920,
        'y': 0,
        'width': 1080,
        'height': 1920,
        'active_workspace': '3',
        'special_workspace': '',
      },
    ],
    'workspaces': [
      {'id': 1, 'name': '1', 'monitor': 'DP-1', 'windows': 2},
      {'id': 3, 'name': '3', 'monitor': 'HDMI-A-1', 'windows': 1},
    ],
  };

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    if (method == 'Set') {
      final value = jsonDecode(arguments[1]) as Map<String, dynamic>;
      final rules = (state['rules'] as List).cast<Map>().where(
        (r) =>
            r['workspace'] != value['workspace'] &&
            r['workspace'] != value['previous'],
      );
      state['rules'] = [
        ...rules,
        if (arguments[0] == setWorkspaceRuleId) value,
      ];
    }
    return state;
  }
}

Future<_Client> _open(WidgetTester tester) async {
  final client = _Client();
  await pump(
    tester,
    WorkspacesPage(
      catalog: catalog,
      page: catalog.page('workspaces'),
      client: client,
    ),
  );
  return client;
}

void main() {
  testWidgets(
    'displays show their workspaces and rules from elsewhere are read-only',
    (tester) async {
      await _open(tester);
      // Open workspaces and a kept workspace that is not open sit on their display.
      for (final ws in ['1', '2', '3']) {
        expect(find.byKey(ValueKey('workspace-chip-$ws')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('workspace-chip-9')), findsOneWidget);
      expect(find.text('On DP-1, Kept when empty'), findsOneWidget);
      expect(find.text('From your other configuration'), findsOneWidget);
      final foreign = find.byKey(const ValueKey('workspace-rule-9'));
      expect(
        find.descendant(of: foreign, matching: find.byType(IconButton)),
        findsNothing,
      );
      // The remove operation has no row of its own.
      expect(
        find.byKey(const ValueKey('workspaces.rule-remove')),
        findsNothing,
      );
      expect(find.text('First window'), findsOneWidget);
    },
  );

  testWidgets('a workspace on the map opens a prefilled rule editor', (
    tester,
  ) async {
    final client = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('workspace-chip-3')));
    await tester.pumpAndSettle();
    expect(find.text('Add a workspace rule'), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-default')), findsOneWidget);
    // A scratchpad cannot be a display's first workspace and takes no name.
    await tester.tap(find.text('Scratchpad').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('workspace-default')), findsNothing);
    expect(find.byKey(const ValueKey('workspace-default-name')), findsNothing);
    await tester.tap(find.text('Numbered'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workspace-persistent')));
    await tester.tap(find.byKey(const ValueKey('workspace-default')));
    await tester.enterText(
      find.byKey(const ValueKey('workspace-default-name')),
      'Chat',
    );
    await tester.tap(find.byKey(const ValueKey('workspace-rule-save')));
    await tester.pumpAndSettle();
    expect(find.text('Add a workspace rule'), findsNothing);
    final set = client.calls.lastWhere((c) => c[0] == 'Set');
    expect(set[1], setWorkspaceRuleId);
    expect(jsonDecode(set[2]), {
      'workspace': '3',
      'monitor': 'HDMI-A-1',
      'default': true,
      'persistent': true,
      'default_name': 'Chat',
      'previous': null,
    });
    expect(
      find.text(
        'On HDMI-A-1, Display starts here, Kept when empty, Named Chat',
      ),
      findsOneWidget,
    );
  });

  testWidgets('editing keeps the previous workspace and remove drops a rule', (
    tester,
  ) async {
    final client = await _open(tester);
    final row = find.byKey(const ValueKey('workspace-rule-2'));
    await tester.tap(
      find.descendant(of: row, matching: find.byTooltip('Edit')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit workspace rule'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('workspace-name')), '4');
    await tester.tap(find.byKey(const ValueKey('workspace-rule-save')));
    await tester.pumpAndSettle();
    final set = jsonDecode(client.calls.last[2]) as Map;
    expect(
      [set['workspace'], set['previous'], set['persistent']],
      ['4', '2', true],
    );
    final edited = find.byKey(const ValueKey('workspace-rule-4'));
    await tester.tap(
      find.descendant(of: edited, matching: find.byTooltip('Remove')),
    );
    await tester.pumpAndSettle();
    expect(client.calls.last.sublist(0, 3), [
      'Set',
      removeWorkspaceRuleId,
      jsonEncode({'workspace': '4'}),
    ]);
    expect(edited, findsNothing);
  });
}
