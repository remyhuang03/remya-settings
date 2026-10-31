import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'features/integration/settings_scheduler.dart';
import 'app.dart';
import 'features/integration/service_controllers.dart';

import 'package:remya_settings_client/remya_settings_client.dart';

import 'features/appearance/data/app_preferences_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  if (kDebugMode) {
    final root = await const MethodChannel('top.remya.paths')
        .invokeMethod<String>('repositoryDirectory');
    if (root != null) AppPreferencesFile.debugRepository = Directory(root);
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      "Remy'a Settings",
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Rust backend dependencies',
    ], await rootBundle.loadString('assets/licenses/rust-dependencies.txt'));
  });
  final client = SettingsClient();
  final preferences = ServicePreferencesController(client);
  final dateTime = ServiceDateTimeController(client);
  final navigation = ValueNotifier<String?>(null);
  final scheduler = SettingsScheduler([preferences.reload, dateTime.reload]);
  runApp(
    RemyaSettingsApp(
      preferences: preferences,
      dateTime: dateTime,
      navigation: navigation,
      scheduler: scheduler,
    ),
  );
  client.changes.listen((change) {
    switch (change.topic) {
      case 'navigation':
        navigation.value = change.value['page'] as String;
        const MethodChannel('top.remya.paths').invokeMethod<void>('show');
      case 'error':
        final message = change.value['message'];
        if (message is String) {
          preferences.reportError(message);
        } else {
          preferences.reload();
        }
      case 'theme':
        preferences.reload();
      case 'date-time':
        dateTime.reload();
    }
  }); // The native runner forwards the initial page separately from VM arguments.
  final page = await const MethodChannel('top.remya.paths')
      .invokeMethod<String>('initialPage');
  navigation.value = page ?? 'home';
  await scheduler.refresh();
}
