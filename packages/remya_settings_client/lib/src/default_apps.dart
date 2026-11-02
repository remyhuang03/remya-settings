import 'dart:convert';

import 'dbus_client.dart';

const defaultAppsTypeSettingId = 'defaults.b131ac5a';
const defaultAppsSearchSettingId = 'defaults.897fdfef';
const defaultAppsSettingIds = {
  defaultAppsTypeSettingId,
  defaultAppsSearchSettingId,
  'defaults.ccac113f',
  'defaults.3adc9929',
  'defaults.c0b97974',
  'defaults.e7fe6be6',
  'defaults.audio',
  'defaults.text',
  'defaults.pdf',
  'defaults.file-manager',
};

extension DefaultAppsClient on SettingsClient {
  Future<Map<String, dynamic>> readDefaultApps() =>
      call('Get', ['default-apps']);
  Future<Map<String, dynamic>> searchDefaultApplications(String query) =>
      call('Get', ['default-applications:$query']);
  Future<Map<String, dynamic>> searchDefaultTypes(String query) =>
      call('Get', ['default-types:$query']);
  Future<Map<String, dynamic>> defaultCandidates(List<String> types) =>
      call('Get', ['default-candidates:${types.join(',')}']);
  Future<Map<String, dynamic>> setDefaultApplication(
    String settingId,
    String application, {
    List<String> types = const [],
  }) => call('Set', [
    settingId,
    jsonEncode({'application': application, 'types': types}),
  ]);
  Future<Map<String, dynamic>> resolveDefaultApps(String source) =>
      call('Resolve', ['default-apps', source]);
}
