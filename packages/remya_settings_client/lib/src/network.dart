import 'dart:convert';

import 'dbus_client.dart';

const wifiEnabledSettingId = 'wifi.enabled';
const wifiAdapterSettingId = 'wifi.adapter';
const wifiDisconnectSettingId = 'wifi.disconnect';
const wifiRefreshSettingId = 'wifi.refresh';
const wifiConnectSettingId = 'wifi.connect';
const networkSignInSettingId = 'network-status.sign-in';
const knownNetworkAddSettingId = 'known-networks.add';
const knownNetworkAutoconnectSettingId = 'known-networks.autoconnect';
const knownNetworkMeteredSettingId = 'known-networks.metered';
const knownNetworkPasswordSettingId = 'known-networks.change-password';
const knownNetworkForgetSettingId = 'known-networks.forget';

extension NetworkClient on SettingsClient {
  Future<Map<String, dynamic>> readNetwork() => call('Get', ['network']);
  Future<Map<String, dynamic>> readNetworkTraffic() =>
      call('Get', ['network-traffic']);
  Future<Map<String, dynamic>> resolveNetwork(String source) =>
      call('Resolve', ['network', source]);
  Future<Map<String, dynamic>> setWifiEnabled(bool enabled) =>
      call('Set', [wifiEnabledSettingId, '$enabled']);
  Future<Map<String, dynamic>> scanWifi() =>
      call('Set', [wifiRefreshSettingId, 'scan']);
  Future<Map<String, dynamic>> connectWifi({
    String? ssid,
    String? uuid,
    String? password,
    String? hiddenSecurity,
  }) => call('Set', [
    wifiConnectSettingId,
    jsonEncode({
      'ssid': ?ssid,
      'uuid': ?uuid,
      'password': ?password,
      'hidden_security': ?hiddenSecurity,
    }),
  ]);
  Future<Map<String, dynamic>> addKnownNetwork({
    required String ssid,
    required String security,
    String? password,
    bool hidden = false,
    bool autoconnect = true,
  }) => call('Set', [
    knownNetworkAddSettingId,
    jsonEncode({
      'ssid': ssid,
      'security': security,
      'password': ?password,
      'hidden': hidden,
      'autoconnect': autoconnect,
    }),
  ]);
  Future<Map<String, dynamic>> changeKnownNetwork(
    String id,
    String uuid,
    Object value,
  ) => call('Set', [
    id,
    jsonEncode({'uuid': uuid, 'value': value}),
  ]);
}
