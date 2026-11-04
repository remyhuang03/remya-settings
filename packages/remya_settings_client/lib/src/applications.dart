import 'dart:convert';

import 'dbus_client.dart';

const installedAppsSettingIds = {
  'installed.15735a25',
  'installed.3bf3689a',
  'installed.765cf6c3',
  'installed.32098ab2',
  'installed.c3c4a29c',
};
const uninstallAppSettingId = 'installed.c3c4a29c';

extension ApplicationsClient on SettingsClient {
  Future<String> formatCalendarDate(String date) async =>
      (await call("Get", ["calendar-date:$date"]))["value"] as String;
  Future<Map<String, dynamic>> readInstalledApplications({
    String query = '',
    String sort = 'name',
    String? source,
  }) => query.isEmpty && sort == 'name' && source == null
      ? call('Get', ['installed-apps'])
      : call('Get', [
          'installed-apps:${jsonEncode({'query': query, 'sort': sort, 'source': source})}',
        ]);
  Future<Map<String, dynamic>> installedApplication(String id) =>
      call('Get', ['installed-app:$id']);
  Future<Map<String, dynamic>> uninstallApplication(String id, String token) =>
      call('Set', [
        uninstallAppSettingId,
        jsonEncode({'id': id, 'token': token}),
      ]);
}

const appImagesInstallSettingId = 'appimages.install';
const appImagesCheckSettingId = 'appimages.check';
const appImagesUpdateSettingId = 'appimages.update';
const appImagesCancelSettingId = 'appimages.cancel';
const appImagesSourceSettingId = 'appimages.source';
const appImagesIntegrateSettingId = 'appimages.integrate';
const appImagesOpenSettingId = 'appimages.open';
const appImagesUninstallSettingId = 'appimages.uninstall';
const appImagesAutoCheckSettingId = 'appimages.auto-check';
const appImagesAutoUpdateSettingId = 'appimages.auto-update';

extension AppImagesClient on SettingsClient {
  Future<Map<String, dynamic>> readAppImages() => call('Get', ['appimages']);
  Future<Map<String, dynamic>> setAppImageSource(
    String id,
    String? source,
    bool updates,
  ) => call('Set', [
    appImagesSourceSettingId,
    jsonEncode({'id': id, 'source': source, 'updates': updates}),
  ]);
}

const inputMethodToolSettingIds = {'time-more.fcitx5', 'time-more.ibus'};

extension InputMethodToolsClient on SettingsClient {
  Future<Map<String, dynamic>> readInputMethodTools() =>
      call('Get', ['input-method-tools']);
  Future<Map<String, dynamic>> openInputMethodTool(String id) =>
      call('Set', [id, 'open']);
}

const externalToolSettingIds = {
  ...inputMethodToolSettingIds,
  'system-more.kde',
  'system-more.gnome',
  'system-more.localsend',
  'appearance-more.qt6ct',
  'appearance-more.kvantum',
  'appearance-more.gtk',
  'appearance-more.gnome-tweaks',
};

extension ExternalToolsClient on SettingsClient {
  Future<Map<String, dynamic>> readExternalTools(String group) =>
      call('Get', ['external-tools:$group']);
  Future<Map<String, dynamic>> openExternalTool(String id) =>
      call('Set', [id, 'open']);
}
