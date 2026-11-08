import 'dart:convert';

import 'dbus_client.dart';

const airplaneEnabledSettingId = 'airplane.enabled';
const airplaneWifiSettingId = 'airplane.wifi';

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
const knownNetworkPrioritySettingId = 'known-networks.priority';
const knownNetworkMacSettingId = 'known-networks.mac';
const knownNetworkIpSettingId = 'known-networks.ip';
const knownNetworkDnsSettingId = 'known-networks.dns';
const connectivityCheckSettingId = 'network-status.connectivity-check';
const ethernetConnectSettingId = 'ethernet.connect';
const ethernetAutoconnectSettingId = 'ethernet.autoconnect';
const ethernetMeteredSettingId = 'ethernet.metered';
const ethernetIpSettingId = 'ethernet.ip';
const ethernetDnsSettingId = 'ethernet.dns';
const vpnConnectSettingId = 'vpn.connect';
const vpnImportSettingId = 'vpn.import';
const vpnRemoveSettingId = 'vpn.remove';
const hotspotEnabledSettingId = 'hotspot.enabled';
const hotspotConfigureSettingId = 'hotspot.configure';
const proxyModeSettingId = 'proxy.mode';
const proxyScriptSettingId = 'proxy.script';
const proxyHttpSettingId = 'proxy.http';
const proxyHttpsSettingId = 'proxy.https';
const proxySocksSettingId = 'proxy.socks';
const proxyIgnoreSettingId = 'proxy.ignore';

extension NetworkClient on SettingsClient {
  Future<Map<String, dynamic>> readAirplane() => call('Get', ['airplane']);
  Future<Map<String, dynamic>> setAirplaneEnabled(bool enabled) =>
      call('Set', [airplaneEnabledSettingId, '$enabled']);
  Future<Map<String, dynamic>> setAirplaneWifiEnabled(bool enabled) =>
      call('Set', [airplaneWifiSettingId, '$enabled']);
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
  Future<Map<String, dynamic>> readProxy() => call('Get', ['proxy']);
  Future<Map<String, dynamic>> setProxy(String id, String value) =>
      call('Set', [id, value]);
  Future<Map<String, dynamic>> configureHotspot({
    required String ssid,
    required String band,
    String? password,
  }) => call('Set', [
    hotspotConfigureSettingId,
    jsonEncode({'ssid': ssid, 'band': band, 'password': ?password}),
  ]);

  /// Changes one preference of a saved connection: `{uuid, value}`.
  Future<Map<String, dynamic>> changeKnownNetwork(
    String id,
    String uuid,
    Object value,
  ) => call('Set', [
    id,
    jsonEncode({'uuid': uuid, 'value': value}),
  ]);
}
