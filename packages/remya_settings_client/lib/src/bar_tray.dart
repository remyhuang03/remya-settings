import 'dart:convert';

import 'dbus_client.dart';

const barFoldedAppsSettingId = 'remya-bar.folded-apps';

extension BarTrayClient on SettingsClient {
  Future<Set<String>> readBarFoldedApps() async =>
      Set<String>.from((await call('Get', [barFoldedAppsSettingId]))['value']);

  Future<Set<String>> setBarAppFolded(String id, bool folded) async =>
      Set<String>.from(
        (await call('Set', [
          barFoldedAppsSettingId,
          jsonEncode({'id': id, 'folded': folded}),
        ]))['value'],
      );
}
