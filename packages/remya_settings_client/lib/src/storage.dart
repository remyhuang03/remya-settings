import 'dart:convert';

import 'dbus_client.dart';

const storageSettingIds = {
  'storage.usage',
  'storage.scan',
  'storage.volumes',
  'storage.mount',
  'storage.eject',
  'storage.label',
  'storage.open',
  'cleanup.trash',
  'cleanup.cache',
  'cleanup.package-cache',
  'cleanup.orphans',
  'cleanup.large-files',
  'cleanup.auto',
  'cleanup.auto-frequency',
  'cleanup.auto-trash',
  'cleanup.auto-cache',
  'cleanup.auto-downloads',
  'cleanup.run-now',
};

extension StorageClient on SettingsClient {
  Future<Map<String, dynamic>> readStorage() => call('Get', ['storage']);
  Future<Map<String, dynamic>> readCleanup() => call('Get', ['cleanup']);
  Future<Map<String, dynamic>> scanStorage() => _storageSet('storage.scan', {});
  Future<Map<String, dynamic>> mountVolume(
    String volume, {
    required bool mount,
  }) => _storageSet('storage.mount', {
    'volume': volume,
    'action': mount ? 'mount' : 'unmount',
  });
  Future<Map<String, dynamic>> ejectDrive(
    String drive, {
    required bool powerOff,
  }) => _storageSet('storage.eject', {
    'drive': drive,
    'action': powerOff ? 'power-off' : 'eject',
  });
  Future<Map<String, dynamic>> renameVolume(String volume, String label) =>
      _storageSet('storage.label', {'volume': volume, 'label': label});
  Future<Map<String, dynamic>> openStorageFolder(String path) =>
      _storageSet('storage.open', {'path': path});
  Future<Map<String, dynamic>> emptyTrash() =>
      _storageSet('cleanup.trash', {'action': 'empty'});
  Future<Map<String, dynamic>> removeCacheFolders(List<String> folders) =>
      _storageSet('cleanup.cache', {'folders': folders});
  Future<Map<String, dynamic>> cleanPackageCache({
    required int keep,
    required bool uninstalled,
  }) => _storageSet('cleanup.package-cache', {
    'keep': keep,
    'uninstalled': uninstalled,
  });
  Future<Map<String, dynamic>> removeOrphanPackages(
    List<({String name, String version})> packages,
  ) => _storageSet('cleanup.orphans', {
    'packages': [
      for (final p in packages) {'name': p.name, 'version': p.version},
    ],
  });
  Future<Map<String, dynamic>> trashLargeFiles(List<String> paths) =>
      _storageSet('cleanup.large-files', {'paths': paths});
  Future<Map<String, dynamic>> automaticCleanup(bool enabled) =>
      _storageSet('cleanup.auto', enabled);
  Future<Map<String, dynamic>> cleanupFrequency(String frequency) =>
      _storageSet('cleanup.auto-frequency', frequency);
  Future<Map<String, dynamic>> cleanupTrashAge(int days) =>
      _storageSet('cleanup.auto-trash', days);
  Future<Map<String, dynamic>> cleanupCacheAge(int days) =>
      _storageSet('cleanup.auto-cache', days);
  Future<Map<String, dynamic>> cleanupDownloadsAge(int days) =>
      _storageSet('cleanup.auto-downloads', days);
  Future<Map<String, dynamic>> runCleanupPolicy() =>
      _storageSet('cleanup.run-now', {});
  Future<Map<String, dynamic>> _storageSet(String id, Object value) =>
      call('Set', [id, jsonEncode(value)]);
}
