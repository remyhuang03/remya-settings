import 'dart:convert';

import 'dbus_client.dart';

const soundOutputDeviceSettingId = 'sound.output-device';
const soundOutputVolumeSettingId = 'sound.output-volume';
const soundOutputMutedSettingId = 'sound.output-muted';
const soundInputDeviceSettingId = 'sound.input-device';
const soundInputVolumeSettingId = 'sound.input-volume';
const soundInputMutedSettingId = 'sound.input-muted';
const soundDeviceVolumeSettingId = 'sound.device-volume';
const soundDeviceMutedSettingId = 'sound.device-muted';
const soundStreamVolumeSettingId = 'sound.stream-volume';
const soundStreamMutedSettingId = 'sound.stream-muted';
const soundStreamDeviceSettingId = 'sound.stream-device';
const soundDevicesSettingId = 'sound.devices';
const soundStreamsSettingId = 'sound.streams';
const soundRefreshSettingId = 'sound.refresh';

extension SoundClient on SettingsClient {
  Future<Map<String, dynamic>> readSound() => call('Get', ['sound']);
  Future<Map<String, dynamic>> setSound(String setting, String request) =>
      call('Set', [setting, request]);
  Future<Map<String, dynamic>> changeSound(
    String setting,
    Map<String, Object?> request,
  ) => setSound(setting, jsonEncode(request));
  Future<Map<String, dynamic>> resolveSound(String source) =>
      call('Resolve', ['sound', source]);
}
