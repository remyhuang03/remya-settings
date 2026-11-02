import 'dart:convert';

import 'dbus_client.dart';

const bluetoothEnabledSettingId = 'bluetooth.enabled';
const bluetoothAdapterSettingId = 'bluetooth.adapter';
const bluetoothScanSettingId = 'bluetooth.scan';
const bluetoothDiscoverableSettingId = 'bluetooth.discoverable';
const bluetoothPairSettingId = 'bluetooth.pair';
const bluetoothCancelSettingId = 'bluetooth.cancel';
const bluetoothRespondSettingId = 'bluetooth.respond';
const bluetoothConnectSettingId = 'bluetooth.connect';
const bluetoothDisconnectSettingId = 'bluetooth.disconnect';
const bluetoothForgetSettingId = 'bluetooth.forget';

extension BluetoothClient on SettingsClient {
  Future<Map<String, dynamic>> readBluetooth() => call('Get', ['bluetooth']);
  Future<Map<String, dynamic>> setBluetooth(
    String id,
    Map<String, dynamic> request,
  ) => call('Set', [id, jsonEncode(request)]);
}
