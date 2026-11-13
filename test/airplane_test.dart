import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/network/presentation/airplane_page.dart';
import 'package:remya_client/settings_contract.dart';

class _Client extends SettingsClient {
  bool enabled = false;
  bool wifi = true;
  bool fail = false;
  final writes = <List<String>>[];

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Set') {
      writes.add(arguments);
      if (fail) throw StateError('Radio permission denied');
      if (arguments.first == airplaneEnabledSettingId) {
        enabled = arguments.last == 'true';
        wifi = !enabled;
      } else {
        wifi = arguments.last == 'true';
        enabled = !wifi;
      }
    }
    return {'available': true, 'enabled': enabled, 'wifi_enabled': wifi};
  }
}

void main() {
  testWidgets(
    'airplane writes use the public service contract and retain failures',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AirplanePage(client: client)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('$airplaneEnabledSettingId-switch')),
      );
      await tester.pumpAndSettle();
      expect(client.writes.single, [airplaneEnabledSettingId, 'true']);
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('$airplaneEnabledSettingId-switch')),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('$airplaneWifiSettingId-switch')),
            )
            .value,
        isFalse,
      );
      client.fail = true;
      await tester.tap(
        find.byKey(const ValueKey('$airplaneWifiSettingId-switch')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Radio permission denied'), findsOneWidget);
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('$airplaneWifiSettingId-switch')),
            )
            .value,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
