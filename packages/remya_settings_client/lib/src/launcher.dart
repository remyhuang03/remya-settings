import 'dart:io';

import 'dbus_client.dart';

Future<void> openRemyaSettings({
  File? debugExecutable,
  String page = 'home',
}) async {
  if (debugExecutable != null) {
    if (!await debugExecutable.exists()) {
      throw const FileSystemException(
        'Build the sibling remya-settings repository with fvm flutter build linux --debug first.',
      );
    }
    await Process.start(debugExecutable.path, ['open', page], mode: .detached);
    return;
  }
  final client = SettingsClient();
  try {
    await client.call('Open', [page]);
  } finally {
    await client.close();
  }
}
