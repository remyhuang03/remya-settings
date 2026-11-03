import 'dart:convert';

import 'dbus_client.dart';

const accountInformationKey = 'account-information';
const accountUsernameSettingId = 'your-info.a1aaf352';
const accountAvatarSettingId = 'your-info.58484bbb';

extension AccountInformationClient on SettingsClient {
  Future<Map<String, dynamic>> readAccountInformation() =>
      call('Get', [accountInformationKey]);

  /// Crop edges are normalized coordinates in the oriented source image.
  Future<Map<String, dynamic>> saveAccountAvatar(
    String path,
    Map<String, double> crop,
  ) => call('Set', [
    accountAvatarSettingId,
    jsonEncode({'path': path, 'crop': crop}),
  ]);
}
