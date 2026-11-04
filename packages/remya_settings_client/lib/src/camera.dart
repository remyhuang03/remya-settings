import 'dart:convert';

import 'dbus_client.dart';

extension CameraClient on SettingsClient {
  Future<Map<String, dynamic>> readCameras() => call('Get', ['cameras']);
  Future<Map<String, dynamic>> changeCamera(
    String field,
    String camera,
    int serial, {
    double? value,
  }) => call('Set', [
    'cameras.$field',
    jsonEncode({'camera': camera, 'serial': serial, 'value': ?value}),
  ]);
  Future<Map<String, dynamic>> resolveCamera(String camera, String source) =>
      call('Resolve', ['cameras:$camera', source]);
}
