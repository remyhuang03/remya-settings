import 'dart:io';

import 'dbus_client.dart';

Future<void> openRemyaSettings({File? debugExecutable}) async {
  if (debugExecutable != null) {
    if (!await debugExecutable.exists()) {
      throw const FileSystemException(
        'Build the sibling remya_settings repository with fvm flutter build linux --debug first.',
      );
    }
    await Process.start(debugExecutable.path, const [], mode: .detached);
    return;
  }
  final client = SettingsClient();
  try {
    await client.call('Open', ['home']);
  } finally {
    await client.close();
  }
}
