import 'dart:convert';

import 'dbus_client.dart';

/// Visible providers, the addable catalog and the Bar preferences.
const aiProvidersSettingId = 'ai.providers';

/// Bar quota preferences: `{pinned, lowPercent, showUsed, ringOrder}`.
const aiBarSettingId = 'ai.bar';

const _aiProviderPrefix = 'ai.provider/';
const _aiCredentialSettingId = 'ai.credential';
const _aiCustomSettingId = 'ai.custom';

/// AI providers tracked by CodexBar and custom OpenAI-compatible endpoints.
/// Every setter returns the refreshed [aiProvidersSettingId] value.
extension AiClient on SettingsClient {
  Future<Map<String, dynamic>> _value(String method, List<String> args) async =>
      Map<String, dynamic>.from((await call(method, args))['value'] as Map);

  Future<Map<String, dynamic>> _set(String id, Map<String, Object?> payload) =>
      _value('Set', [id, jsonEncode(payload)]);

  Future<Map<String, dynamic>> readAi() =>
      _value('Get', [aiProvidersSettingId]);

  /// `{pinned, lowPercent, showUsed, ringOrder}` without probing providers; cheap enough to poll.
  Future<Map<String, dynamic>> readAiBar() => _value('Get', [aiBarSettingId]);

  /// `{provider, usage, modelsDev: {status, provider, models}}`.
  Future<Map<String, dynamic>> readAiProvider(String id) =>
      _value('Get', ['$_aiProviderPrefix$id']);

  Future<Map<String, dynamic>> setAiProvider(
    String id, {
    bool? enabled,
    String? source,
  }) => _set(aiProvidersSettingId, {
    'id': id,
    'enabled': ?enabled,
    'source': ?source,
  });

  Future<Map<String, dynamic>> setAiBar({
    List<String>? pinned,
    int? lowPercent,
    bool? showUsed,
    String? ringOrder,
  }) => _set(aiBarSettingId, {
    'pinned': ?pinned,
    'lowPercent': ?lowPercent,
    'showUsed': ?showUsed,
    'ringOrder': ?ringOrder,
  });

  /// Exactly one of [apiKey], [cookie] or [clear]. The secret travels to the
  /// service only; replies never contain it.
  Future<Map<String, dynamic>> setAiCredential(
    String id, {
    String? apiKey,
    String? cookie,
    bool clear = false,
  }) => _set(_aiCredentialSettingId, {
    'id': id,
    'apiKey': ?apiKey,
    'cookie': ?cookie,
    if (clear) 'clear': true,
  });

  Future<Map<String, dynamic>> addAiCustomProvider({
    required String name,
    required String baseUrl,
    String? modelsDev,
    String? apiKey,
  }) => _set(_aiCustomSettingId, {
    'add': {
      'name': name,
      'baseUrl': baseUrl,
      'modelsDev': ?modelsDev,
      'apiKey': ?apiKey,
    },
  });

  Future<Map<String, dynamic>> removeAiCustomProvider(String id) =>
      _set(_aiCustomSettingId, {'remove': id});
}
