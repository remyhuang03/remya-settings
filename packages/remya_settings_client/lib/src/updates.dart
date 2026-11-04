import 'dbus_client.dart';

const updatesCheckSettingId = 'updates.check';
const updatesUpgradeSettingId = 'updates.upgrade';
const updatesIncludeHeldSettingId = 'updates.include-held';
const updatesRetrySettingId = 'updates.retry';
const updatesStatusSettingId = 'updates.status';
const updatesOutputSettingId = 'updates.output';
const updatesAutomaticSettingId = 'updates.automatic';
const activeHoursStartSettingId = 'active-hours.e8868af6';
const activeHoursEndSettingId = 'active-hours.a0bb9f49';

extension UpdatesClient on SettingsClient {
  Future<Map<String, dynamic>> automaticUpdates(bool enabled) =>
      call('Set', [updatesAutomaticSettingId, '$enabled']);
  Future<Map<String, dynamic>> activeHoursStart(String localTime) =>
      call('Set', [activeHoursStartSettingId, localTime]);
  Future<Map<String, dynamic>> activeHoursEnd(String localTime) =>
      call('Set', [activeHoursEndSettingId, localTime]);
  Future<Map<String, dynamic>> readUpdates() => call('Get', ['updates']);
  Future<Map<String, dynamic>> checkUpdates() =>
      call('Set', [updatesCheckSettingId, 'check']);
  Future<Map<String, dynamic>> upgradePackages() =>
      call('Set', [updatesUpgradeSettingId, 'upgrade']);
  Future<Map<String, dynamic>> includeHeldPackages(bool value) =>
      call('Set', [updatesIncludeHeldSettingId, '$value']);
  Future<Map<String, dynamic>> retryUpdates(bool value) =>
      call('Set', [updatesRetrySettingId, '$value']);
}
