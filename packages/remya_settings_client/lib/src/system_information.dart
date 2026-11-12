import 'dbus_client.dart';

const systemInformationKey = 'system-information';
const systemInformationSettingIds = {
  'about.4433eb13',
  'about.b4366749',
  'about.d014ab77',
  'about.96af9884',
  'about.d0a7f225',
  'about.manufacturer',
  'about.model',
  'about.model-version',
  'about.board-manufacturer',
  'about.board-model',
  'about.firmware-manufacturer',
  'about.firmware-version',
  'about.firmware-date',
  'about.cpu-cores',
  'about.cpu-threads',
  'about.kernel-version',
  'about.desktop-version',
  'about.desktop-config-errors',
};

typedef SystemInformationReader = Future<Map<String, dynamic>> Function();

extension SystemInformationClient on SettingsClient {
  /// Fresh observations keyed by stable setting ID, each with value/error.
  Future<Map<String, dynamic>> readSystemInformation() =>
      call('Get', [systemInformationKey]);
}

const hostnameSettingId = 'about.0f142010';

String? validateHostname(String name) {
  if (name.isEmpty ||
      name.length > 63 ||
      !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(name)) {
    return 'Use 1–63 lowercase letters, digits or hyphens. Start and end with a letter or digit.';
  }
  return null;
}

extension HostnameClient on SettingsClient {
  Future<Map<String, dynamic>> readHostname() => call('Get', ['hostname']);
  Future<Map<String, dynamic>> renameHostname(String name) =>
      call('Set', [hostnameSettingId, name]);
  Future<Map<String, dynamic>> resolveHostname(String source) async =>
      (await call('Resolve', ['hostname', source]))['hostname']
          as Map<String, dynamic>;
}
