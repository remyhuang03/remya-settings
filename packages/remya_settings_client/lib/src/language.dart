import 'dart:convert';

import 'dbus_client.dart';

const displayLanguageId = 'language.display';
const regionalFormatId = 'language.format';

/// The `input` options for keyboard layouts: an ordered list of
/// `{layout, variant}` (the first is the default) and the comma-separated
/// XKB options, which include the layout switching shortcut (`grp:`).
const keyboardLayoutsId = 'language.keyboard-layouts';
const keyboardOptionsId = 'language.keyboard-options';

/// Display language (`LANG`) and regional format (`LC_TIME`, `LC_NUMERIC`,
/// `LC_MONETARY`, `LC_PAPER`, `LC_MEASUREMENT`) through systemd-localed.
/// They apply to programs started after the next sign-in.
extension LanguageClient on SettingsClient {
  Future<Map<String, dynamic>> readLanguage() => call('Get', ['language']);

  /// Generated locales as `{options: [{id, label}]}`.
  Future<Map<String, dynamic>> readLocales() => call('Get', ['locales']);

  /// Sets [displayLanguageId] to an installed locale, or [regionalFormatId]
  /// to one ("" follows the display language).
  Future<Map<String, dynamic>> setLanguage(String id, String locale) =>
      call('Set', [id, jsonEncode(locale)]);

  Future<Map<String, dynamic>> resolveLanguage(String source) =>
      call('Resolve', ['language', source]);

  /// Sample date, time, weekday, number, currency, measurement and paper
  /// formatted with [locale].
  Future<Map<String, dynamic>> previewFormat(String locale) =>
      call('Get', ['format-preview:$locale']);

  /// xkeyboard-config layouts as `{layouts: [{id, label, variants: [{id, label}]}]}`.
  Future<Map<String, dynamic>> readKeyboardLayouts() =>
      call('Get', ['keyboard-layouts']);
}
