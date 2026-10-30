import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:toml/toml.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../domain/app_preferences.dart';

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

  Future<void> save(AppPreferences preferences) async {
    var target = file;
    if (await FileSystemEntity.isLink(target.path)) {
      target = File(await target.resolveSymbolicLinks());
    }
    await target.parent.create(recursive: true);
    final temporary = await target.parent.createTemp('.remya-settings-');
    try {
      final staged = File('${temporary.path}/config.toml');
      await staged.writeAsString(
        '# Remy\'a Settings app preferences\n${TomlDocument.fromMap(preferences.toMap())}\n',
        flush: true,
      );
      final mode = await target.exists()
          ? (await target.stat()).mode & 0x1ff
          : 0x180;
      final result = await Process.run('chmod', [
        mode.toRadixString(8),
        '--',
        staged.path,
      ]);
      if (result.exitCode != 0) {
        throw FileSystemException(
          'Unable to preserve config permissions',
          target.path,
        );
      }
      await staged.rename(target.path);
    } finally {
      await temporary.delete(recursive: true);
    }
  }
}
