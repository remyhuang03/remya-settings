import 'dart:convert';

import 'dbus_client.dart';

const keepAwakeSettingId = 'power.keep-awake';
const energySaverOffThresholdId = 'battery-saver.off-threshold';
const energySaverOnThresholdId = 'battery-saver.9b0caf70';

extension PowerClient on SettingsClient {
  Future<Map<String, dynamic>> readPower() => call('Get', ['power']);
  Future<Map<String, dynamic>> setPower(String id, Object value) =>
      call('Set', [id, jsonEncode(value)]);
  Future<Map<String, dynamic>> readKeepAwake() =>
      call('Get', [keepAwakeSettingId]);
  Future<Map<String, dynamic>> setKeepAwake(bool enabled) =>
      setPower(keepAwakeSettingId, enabled);
  Future<Map<String, dynamic>> resolvePower(String source) =>
      call('Resolve', ['power', source]);
  Future<Map<String, dynamic>> batteryHistory({
    required int from,
    required int to,
    int after = 0,
    int limit = 1000,
  }) => call('Get', [
    'battery-history:${jsonEncode({'from': from, 'to': to, 'after': after, 'limit': limit})}',
  ]);
}
