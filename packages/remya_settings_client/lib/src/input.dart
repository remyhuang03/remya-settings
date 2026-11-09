import 'dart:convert';

import 'dbus_client.dart';

const addShortcutId = 'keyboard-shortcuts.add';
const removeShortcutId = 'keyboard-shortcuts.remove';
const disableShortcutId = 'keyboard-shortcuts.disable';
const recordShortcutId = 'keyboard-shortcuts.record';
const setWorkspaceRuleId = 'workspaces.rule-set';
const removeWorkspaceRuleId = 'workspaces.rule-remove';

/// Settings-owned Hyprland options: `input` (mouse, touchpad and keyboard
/// shortcuts) and `desktop` (window layout, window appearance, animations,
/// cursor behavior, workspaces and workspace rules, blur, fallback background,
/// display wake, the compositor font and the compositor bell).
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

  /// Adds or replaces the Settings rule for [workspace] (a number,
  /// `name:<name>` or `special:<name>`); [previous] names the rule being edited.
  Future<Map<String, dynamic>> setWorkspaceRule({
    required String workspace,
    String monitor = '',
    bool isDefault = false,
    bool persistent = false,
    String defaultName = '',
    String? previous,
  }) => setInput(setWorkspaceRuleId, {
    'workspace': workspace,
    'monitor': monitor,
    'default': isDefault,
    'persistent': persistent,
    'default_name': defaultName,
    'previous': previous,
  });

  Future<Map<String, dynamic>> removeWorkspaceRule(String workspace) =>
      setInput(removeWorkspaceRuleId, {'workspace': workspace});

  /// Suspends compositor shortcuts so a recorder receives every key.
  Future<Map<String, dynamic>> recordShortcut(bool recording) =>
      setInput(recordShortcutId, recording);
}
