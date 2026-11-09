import 'dart:convert';

import 'dbus_client.dart';

const addShortcutId = 'keyboard-shortcuts.add';
const removeShortcutId = 'keyboard-shortcuts.remove';
const disableShortcutId = 'keyboard-shortcuts.disable';
const recordShortcutId = 'keyboard-shortcuts.record';

/// Settings-owned Hyprland options: `input` (mouse, touchpad and keyboard
/// shortcuts) and `desktop` (window blur, fallback background and display wake).
extension InputClient on SettingsClient {
  Future<Map<String, dynamic>> readHyprOptions(String feature) =>
      call('Get', [feature]);
  Future<Map<String, dynamic>> resolveHyprOptions(
    String feature,
    String source,
  ) => call('Resolve', [feature, source]);

  /// Sets any `input` or `desktop` option; the service routes it by ID.
  Future<Map<String, dynamic>> setInput(String id, Object value) =>
      call('Set', [id, jsonEncode(value)]);

  /// The canonical spelling of [keys] and the live shortcuts already using it.
  Future<Map<String, dynamic>> lookupShortcut(String keys) => call('Get', [
    'keyboard-shortcuts.lookup:${jsonEncode({'keys': keys})}',
  ]);

  /// Suspends compositor shortcuts so a recorder receives every key.
  Future<Map<String, dynamic>> recordShortcut(bool recording) =>
      setInput(recordShortcutId, recording);
}
