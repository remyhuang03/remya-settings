import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';
import 'package:remya_settings/features/power/presentation/power_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

class _Client extends SettingsClient {
  final requests = <List<String>>[];
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    requests.add([method, ...arguments]);
    return {
      'available': true,
      'system': {
        'profile': 'balanced',
        'profiles': ['balanced', 'power-saver'],
        'has_backlight': true,
      },
      'saved': {'threshold': 20, 'include_ac': false, 'dim': false},
      'conflict': false,
    };
  }
}

void main() {
  testWidgets('saver options invoke the public contract', (tester) async {
    final catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    final client = _Client();
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PowerPage(
              page: catalog.page('battery-saver'),
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Also enable when plugged in'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(
      client.requests,
      contains(equals(['Set', 'battery-saver.743773bd', 'true'])),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
