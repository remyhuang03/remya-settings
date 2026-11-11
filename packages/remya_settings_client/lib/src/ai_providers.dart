import 'dart:convert';

import 'dbus_client.dart';

const aiProvidersSettingId = 'ai-providers.tracking';

extension AiProvidersClient on SettingsClient {
  Future<Map<String, dynamic>> readAiProviders() async =>
      Map<String, dynamic>.from(
        (await call('Get', [aiProvidersSettingId]))['value'] as Map,
      );

  Future<Map<String, dynamic>> setAiProvider(String id, bool enabled) async =>
      Map<String, dynamic>.from(
        (await call('Set', [
              aiProvidersSettingId,
              jsonEncode({'id': id, 'enabled': enabled}),
            ]))['value']
            as Map,
      );
}
