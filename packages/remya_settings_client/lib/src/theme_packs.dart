import 'dart:convert';

import 'dbus_client.dart';

const cursorThemeId = 'cursor.theme';
const cursorSizeId = 'cursor.size';
const iconThemeId = 'themes.icon-theme';
const cursorInstallId = 'cursor.install';
const cursorRemoveId = 'cursor.remove';
const iconInstallId = 'themes.icon-install';
const iconRemoveId = 'themes.icon-remove';

/// Installed cursor and icon theme packs and the selected themes (`themes`).
extension ThemePacksClient on SettingsClient {
  Future<Map<String, dynamic>> readThemePacks() => call('Get', ['themes']);

  /// PNG previews (base64) of a cursor theme near [size] pixels.
  Future<Map<String, dynamic>> cursorPreview(String theme, int size) =>
      call('Get', ['cursor-preview:$theme@$size']);

  /// Selects a theme or size, or installs (a path) or removes (a name) a pack.
  Future<Map<String, dynamic>> setThemePack(String id, Object value) =>
      call('Set', [id, jsonEncode(value)]);

  Future<Map<String, dynamic>> resolveThemePacks(String source) =>
      call('Resolve', ['themes', source]);
}
