import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:toml/toml.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../domain/app_preferences.dart';
import '../../integration/settings_file.dart';

class AppPreferencesFile {
  const AppPreferencesFile(this.file);
  final File file;

  static Directory? debugRepository;

  static File resolve({
    bool isDebug = kDebugMode,
    Map<String, String>? environment,
    Directory? workingDirectory,
  }) {
    return settingsConfigFile(
      isDebug: isDebug,
      repositoryDirectory: workingDirectory ?? debugRepository,
      environment: environment,
    );
  }

  Future<AppPreferences?> load() async {
    if (await FileSystemEntity.type(file.path, followLinks: false) ==
        .notFound) {
      return null;
    }
    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      throw const FormatException('App preferences file is empty');
    }
    return AppPreferences.fromMap(TomlDocument.parse(content).toMap());
  }

  Future<void> save(AppPreferences preferences) => writeSettingsFile(
    file,
    '# Remy\'a Settings app preferences\n${TomlDocument.fromMap(preferences.toMap())}\n',
  );
}
