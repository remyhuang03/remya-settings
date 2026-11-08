import 'dart:convert';

import 'dbus_client.dart';

const startupSettingIds = {
  'startup.apps',
  'startup.add-app',
  'startup.add-command',
  'startup.remove',
};

class StartupEntry {
  const StartupEntry(this.raw);
  final Map raw;
  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  String get comment => raw['comment'] as String;
  String get exec => raw['exec'] as String;
  String? get icon => raw['icon'] as String?;
  String get origin => raw['origin'] as String;
  bool get enabled => raw['enabled'] as bool;
  bool get removable => raw['removable'] as bool;
  String? get status => raw['status'] as String?;
}

extension StartupClient on SettingsClient {
  Future<Map<String, dynamic>> readStartup() => call('Get', ['startup']);
  Future<Map<String, dynamic>> startupCandidates(String query) =>
      call('Get', ['startup-candidates:$query']);
  Future<Map<String, dynamic>> setStartupEnabled(String id, bool enabled) =>
      changeStartup('startup.apps', {'id': id, 'enabled': enabled});
  Future<Map<String, dynamic>> addStartupApplication(String application) =>
      changeStartup('startup.add-app', {'application': application});
  Future<Map<String, dynamic>> addStartupCommand(String name, String command) =>
      changeStartup('startup.add-command', {'name': name, 'command': command});
  Future<Map<String, dynamic>> removeStartupEntry(String id) =>
      changeStartup('startup.remove', {'id': id});
  Future<Map<String, dynamic>> changeStartup(
    String setting,
    Map<String, Object> value,
  ) => call('Set', [setting, jsonEncode(value)]);
  Future<Map<String, dynamic>> resolveStartup(String source) =>
      call('Resolve', ['startup', source]);
}
