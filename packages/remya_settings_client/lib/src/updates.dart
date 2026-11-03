import 'dbus_client.dart';

const updatesCheckSettingId = 'updates.check';
const updatesUpgradeSettingId = 'updates.upgrade';
const updatesIncludeHeldSettingId = 'updates.include-held';
const updatesRetrySettingId = 'updates.retry';
const updatesStatusSettingId = 'updates.status';
const updatesOutputSettingId = 'updates.output';
const updatesAutomaticSettingId = 'updates.automatic';
const updatesDailyTimeSettingId = 'updates.daily-time';

extension UpdatesClient on SettingsClient {
  Future<Map<String, dynamic>> automaticUpdates(bool enabled) =>
      call('Set', [updatesAutomaticSettingId, '$enabled']);
  Future<Map<String, dynamic>> dailyUpdateTime(String localTime) =>
      call('Set', [updatesDailyTimeSettingId, localTime]);
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
