import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

void main() {
  test(
    'service snapshots and signals use the same validated theme contract',
    () async {
      final client = _Client();
      final preferences = SettingsThemeController.service(client: client);
      await preferences.start();
      expect(preferences.error, isNull);
      expect(preferences.theme.mode, ThemeMode.dark);
      expect(preferences.theme.styleVariant, DynamicSchemeVariant.neutral);
      client.current = const ThemeConfig(styleVariant: 'vibrant').toMap();
      client.events.add((topic: 'theme', value: client.current));
      expect(preferences.theme.mode, ThemeMode.light);
      expect(preferences.theme.styleVariant, DynamicSchemeVariant.vibrant);
      final valid = preferences.theme;
      client.events.add((topic: 'theme', value: {'version': 999}));
      expect(preferences.error, isNotNull);
      expect(preferences.theme, same(valid));
      await preferences.reload();
      expect(preferences.error, isNull);
      client.failure = StateError('Service unavailable');
      await preferences.reload();
      expect(preferences.error, isNotNull);
      expect(preferences.theme.styleVariant, DynamicSchemeVariant.vibrant);
      client.failure = null;
      await preferences.reload();
      expect(preferences.error, isNull);
      preferences.dispose();
      expect(client.closed, isTrue);
    },
  );
}

class _Client extends SettingsClient {
  final events = StreamController<SettingsChange>.broadcast(sync: true);
  Map<String, dynamic> current = const ThemeConfig(
    styleVariant: 'neutral',
    mode: 'dark',
  ).toMap();
  Object? failure;
  bool closed = false;

  @override
  Stream<SettingsChange> get changes => events.stream;

  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (failure case final error?) throw error;
    return current;
  }

  @override
  Future<void> close() async {
    closed = true;
    await events.close();
    await super.close();
  }
}
