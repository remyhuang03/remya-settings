import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/printers/presentation/printers_page.dart';
import 'package:remya_client/settings_contract.dart';

import 'input_test.dart' show catalog, pump;

class _Client extends SettingsClient {
  final calls = <List<String>>[];
  bool reject = false;

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    if (method == 'Set' && reject) throw 'lpadmin: Forbidden';
    return {
      'default': null,
      'error': null,
      'printers': [
        {
          'name': 'HP_Smart_Tank_510_series',
          'description': 'HP Smart Tank 510 series',
          'location': '',
          'state': 'stopped',
          'reason': 'Out of paper',
          'accepting': true,
          'default': false,
          'jobs': [
            {'id': 'HP_Smart_Tank_510_series-7', 'user': 'remy', 'size': 2048},
          ],
        },
      ],
    };
  }
}

void main() {
  testWidgets(
    'a printer shows its state, confirms removal and keeps failures',
    (tester) async {
      final client = _Client();
      await pump(
        tester,
        PrintersPage(client: client, page: catalog.page('printers')),
      );
      expect(find.text('HP Smart Tank 510 series'), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.text('Out of paper'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('1 job waiting'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(client.calls.where((c) => c.first == 'Set'), isEmpty);

      client.reject = true;
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(client.calls.last.sublist(0, 2), ['Get', 'printers']);
      expect(client.calls.where((c) => c.first == 'Set').single, [
        'Set',
        removePrinterId,
        jsonEncode({'name': 'HP_Smart_Tank_510_series'}),
      ]);
      // A poll after the rejected write must not hide the error.
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('lpadmin: Forbidden'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
