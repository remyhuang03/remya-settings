import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/ai/presentation/ai_add_provider_dialog.dart';
import 'package:remya_settings/features/ai/presentation/ai_usage_page.dart';
import 'package:remya_settings_client/settings_contract.dart';

import 'input_test.dart' show pump;

Map<String, dynamic> _row(String id) => {
  'id': id,
  'name': id[0].toUpperCase() + id.substring(1),
  'kind': 'codexbar',
  'status': 'ready',
  'enabled': true,
  'windows': const [],
};

/// Answers `ai.providers` and records every Set.
class _Client extends SettingsClient {
  final sets = <List<String>>[];
  List<String> pinned = ['claude', 'codex', 'gemini'];
  bool showUsed = false;
  String ringOrder = '5h-outer';

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Set') {
      sets.add(arguments);
      final body = jsonDecode(arguments[1]) as Map;
      if (body['pinned'] case final List list) {
        pinned = [for (final id in list) id as String];
      }
      if (body['showUsed'] case final bool used) showUsed = used;
      if (body['ringOrder'] case final String order) ringOrder = order;
    }
    return {
      'id': aiProvidersSettingId,
      'value': {
        'codexbar': {'available': true, 'version': '0.84.0'},
        'providers': [
          for (final id in ['claude', 'codex', 'gemini', 'kimi']) _row(id),
        ],
        'catalog': const [],
        'bar': {
          'pinned': pinned,
          'lowPercent': 20,
          'showUsed': showUsed,
          'ringOrder': ringOrder,
        },
      },
    };
  }
}

void main() {
  testWidgets('a fourth provider cannot be pinned until one is hidden', (
    tester,
  ) async {
    final client = _Client();
    await pump(tester, AiUsagePage(client: client));
    Finder show(String id) => find.descendant(
      of: find.byKey(ValueKey('ai-other-$id')),
      matching: find.byWidgetPredicate((widget) => widget is TextButton),
    );
    expect(tester.widget<TextButton>(show('kimi')).onPressed, isNull);

    await tester.tap(find.byTooltip('Hide from bar').first);
    await tester.pumpAndSettle();
    expect(client.pinned, ['codex', 'gemini']);
    expect(tester.widget<TextButton>(show('kimi')).onPressed, isNotNull);
    await tester.tap(show('kimi'));
    await tester.pumpAndSettle();
    expect(client.pinned, ['codex', 'gemini', 'kimi']);

    await tester.tap(find.text('Used'));
    await tester.pumpAndSettle();
    expect(client.showUsed, isTrue);

    await tester.tap(find.text('Inner 5h / Outer 1w'));
    await tester.pumpAndSettle();
    expect(client.ringOrder, '5h-inner');
  });

  testWidgets('a custom endpoint needs https unless it is local', (
    tester,
  ) async {
    final client = _Client();
    await pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) =>
                AiAddProviderDialog(client: client, catalog: const []),
          ),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Custom endpoint'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Mine');
    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'http://api.example.com/v1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an https URL'), findsOneWidget);
    expect(client.sets, isEmpty);
  });
}
