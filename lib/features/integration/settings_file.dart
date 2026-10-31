import 'dart:io';

Future<void> writeSettingsFile(File file, String content) async {
  var target = file;
  if (await FileSystemEntity.isLink(target.path)) {
    target = File(await target.resolveSymbolicLinks());
  }
  await target.parent.create(recursive: true);
  final temporary = await target.parent.createTemp('.remya-settings-');
  try {
    final staged = File('${temporary.path}/config.toml');
    await staged.writeAsString(content, flush: true);
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
