import 'dart:convert';

import 'dbus_client.dart';

const barSidebarLayoutSettingId = 'remya-bar.sidebar-layout';

extension SidebarClient on SettingsClient {
  Future<List<String>> readSidebarLayout() async => List<String>.from(
    (await call('Get', [barSidebarLayoutSettingId]))['value'],
  );

  Future<List<String>> setSidebarLayout(
    List<String> expected,
    List<String> tiles,
  ) async => List<String>.from(
    (await call('Set', [
      barSidebarLayoutSettingId,
      jsonEncode({'expected': expected, 'tiles': tiles}),
    ]))['value'],
  );
}
