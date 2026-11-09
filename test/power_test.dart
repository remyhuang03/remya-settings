import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/power/presentation/power_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings_client/settings_contract.dart';

final _catalog = SettingsCatalog.fromJson(
  jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
      as Map<String, dynamic>,
);

class _Client extends SettingsClient {
  _Client({required this.canLock});
  final bool canLock;
  final calls = <List<String>>[];
  final timeouts = <String, Object>{
    'screen': 600,
    'sleep': 1200,
    'lock': 300,
    'lock_before_sleep': true,
  };

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  Map<String, dynamic> get _power => {
    'available': true,
    'conflict': false,
    'error': null,
    'saved': {'profile': 'balanced', 'timeouts': timeouts},
    'system': {
      'profile': 'balanced',
      'profiles': ['balanced'],
      'timeouts': timeouts,
      'can_lock': canLock,
    },
  };

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add([method, ...arguments]);
    if (method == 'Set' && arguments[0] == 'power.lock-before-sleep') {
      timeouts['lock_before_sleep'] = jsonDecode(arguments[1]) as bool;
    }
    return switch (arguments.first) {
      'desktop' || 'power.wake-key' || 'power.wake-pointer' => {
        'options': {'power.wake-key': true, 'power.wake-pointer': false},
        'conflict': false,
      },
      keepAwakeSettingId => {'value': false},
      _ => _power,
    };
  }
}

Future<void> _pump(WidgetTester tester, _Client client) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 2400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: PowerPage(
            catalog: _catalog,
            page: _catalog.page('power'),
            client: client,
            onPage: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('the idle timeline orders steps and lock rows need lock_cmd', (
    tester,
  ) async {
    final client = _Client(canLock: true);
    await _pump(tester, client);
    expect(find.byKey(const ValueKey('idle-timeline')), findsOneWidget);
    expect(
      find.text(
        'After 5 min, the session locks. After 10 min, the screen turns off. '
        'After 20 min, the computer locks and sleeps.',
      ),
      findsOneWidget,
    );
    final lockSleep = find.descendant(
      of: find.byKey(const ValueKey('power.lock-before-sleep')),
      matching: find.byType(Switch),
    );
    await tester.tap(lockSleep);
    await tester.pump();
    await tester.pump();
    expect(
      client.calls.map((c) => c.join(' ')),
      contains('Set power.lock-before-sleep false'),
    );

    await tester.pumpWidget(const SizedBox());
    final unlockable = _Client(canLock: false);
    await _pump(tester, unlockable);
    expect(find.byKey(const ValueKey('power.lock-after')), findsNothing);
    expect(find.textContaining('sets lock_cmd'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
