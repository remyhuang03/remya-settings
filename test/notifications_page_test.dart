import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/notifications/presentation/notifications_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';
import 'package:remya_settings_client/settings_contract.dart';

class _NotificationClient extends SettingsClient {
  final writes = <List<String>>[];
  var preferences = const NotificationPreferences().toJson();

  @override
  Stream<SettingsChange> get changes => const Stream.empty();

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (method == 'Set') {
      writes.add(arguments);
      if (arguments.first == quietScheduleSettingId) {
        preferences = {...preferences, 'schedule': arguments.last == 'true'};
      }
      return {'value': arguments.last};
    }
    return {'value': preferences};
  }
}

void main() {
  testWidgets('notification pages edit live preferences', (tester) async {
    final client = _NotificationClient();
    final navigation = ValueNotifier<String?>('notifications');
    final catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
    tester.view.physicalSize = const Size(1200, 2400);
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
    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.text('Popup duration'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(client.writes.last, [notificationDndSettingId, 'true']);

    final link = find.byKey(
      const ValueKey('open-page-notifications.automatic-dnd'),
    );
    await tester.ensureVisible(link);
    await tester.pumpAndSettle();
    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(
      tester.widget<NotificationsPage>(find.byType(NotificationsPage)).page.id,
      'quiet-schedule',
    );
    // Schedule details stay hidden until the schedule is on.
    expect(find.text('Start time'), findsNothing);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(client.writes.last, [quietScheduleSettingId, 'true']);
    expect(find.text('Start time'), findsOneWidget);
    expect(find.text('22:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
