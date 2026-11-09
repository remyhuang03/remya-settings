import 'dart:convert';

import 'dbus_client.dart';

/// GNOME `text-scaling-factor`, 0.5 to 3.0.
const textScaleId = 'text-size.scale';

/// Text size (`text-size`): saved and live scaling factor and conflicts.
extension TextSizeClient on SettingsClient {
  Future<Map<String, dynamic>> readTextSize() => call('Get', ['text-size']);

  Future<Map<String, dynamic>> setTextScale(double factor) =>
      call('Set', [textScaleId, jsonEncode(factor)]);

  Future<Map<String, dynamic>> resolveTextSize(String source) =>
      call('Resolve', ['text-size', source]);
}
