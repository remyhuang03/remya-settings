import 'dart:convert';

import 'dbus_client.dart';

const addShortcutId = 'keyboard-shortcuts.add';
const removeShortcutId = 'keyboard-shortcuts.remove';
const disableShortcutId = 'keyboard-shortcuts.disable';
const recordShortcutId = 'keyboard-shortcuts.record';

/// Mouse, touchpad and keyboard shortcut settings on Hyprland.
extension InputClient on SettingsClient {
  Future<Map<String, dynamic>> readInput() => call('Get', ['input']);
  Future<Map<String, dynamic>> setInput(String id, Object value) =>
      call('Set', [id, jsonEncode(value)]);
  Future<Map<String, dynamic>> resolveInput(String source) =>
      call('Resolve', ['input', source]);

  /// The canonical spelling of [keys] and the live shortcuts already using it.
  Future<Map<String, dynamic>> lookupShortcut(String keys) => call('Get', [
    'keyboard-shortcuts.lookup:${jsonEncode({'keys': keys})}',
  ]);

  /// Suspends compositor shortcuts so a recorder receives every key.
  Future<Map<String, dynamic>> recordShortcut(bool recording) =>
      setInput(recordShortcutId, recording);
}
