import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/clipboard/presentation/clipboard_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings_client/settings_contract.dart';

class _LauncherSettings extends SettingsClient {
  final signals = StreamController<SettingsChange>.broadcast();
  final writes = <List<String>>[];
  final preferences = <String, Object>{
    'enabled': true,
    'maxItems': 500,
    'retentionDays': 30,
  };
  bool available = false;

  @override
  Stream<SettingsChange> get changes => signals.stream;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (!available) throw StateError('Launcher is unavailable');
    if (method == 'Get') return {'value': preferences};
    writes.add(arguments);
    switch (arguments.first) {
      case clipboardHistoryEnabledId:
        preferences['enabled'] = arguments.last == 'true';
      case clipboardMaxItemsId:
        preferences['maxItems'] = int.parse(arguments.last);
    }
    return {};
  }
}

void main() {
  testWidgets('clipboard page applies valid edits and confirms clearing', (
    tester,
  ) async {
    final client = _LauncherSettings();
    addTearDown(client.signals.close);
    final navigation = ValueNotifier<String?>('clipboard');
    addTearDown(navigation.dispose);
    final catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    tester.view.physicalSize = const Size(1100, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsShell(
          catalog: catalog,
          navigation: navigation,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ClipboardPage), findsOneWidget);
    expect(find.textContaining('Launcher is unavailable'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);

    client.available = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(client.writes.single, [clipboardHistoryEnabledId, 'false']);

    await tester.tap(find.text('500 items'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '-40');
    await tester.tap(find.text('Set limit'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a whole number from 1 to 5000.'), findsOneWidget);
    expect(client.writes, hasLength(1));
    await tester.enterText(find.byType(TextFormField), '40');
    await tester.tap(find.text('Set limit'));
    await tester.pumpAndSettle();
    expect(client.writes.last, [clipboardMaxItemsId, '40']);
    expect(find.text('40 items'), findsOneWidget);

    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(client.writes, hasLength(2));
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Clear history'),
      ),
    );
    await tester.pumpAndSettle();
    expect(client.writes.last, [clipboardClearHistoryId, 'true']);

    client.available = false;
    client.signals.add((topic: clipboardMaxItemsId, value: {}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Launcher is unavailable'), findsOneWidget);
    expect(find.text('40 items'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
