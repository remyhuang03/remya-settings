import 'dart:convert';

import 'dbus_client.dart';

const barSidebarLayoutSettingId = 'remya-bar.sidebar-layout';
const barKeyboardPreviewSettingId = 'remya-bar.keyboard-preview';

extension SidebarClient on SettingsClient {
  Future<bool> readBarKeyboardPreview() async =>
      (await call('Get', [barKeyboardPreviewSettingId]))['value'] as bool;

  Future<bool> setBarKeyboardPreview(bool enabled) async =>
      (await call('Set', [barKeyboardPreviewSettingId, '$enabled']))['value']
          as bool;

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
