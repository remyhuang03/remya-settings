import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'theme.dart';
import 'theme_config.dart';
import 'dbus_client.dart';

class SettingsThemeController extends ChangeNotifier {
  SettingsThemeController(this.resolveFile) : _client = null;
  SettingsThemeController.service({SettingsClient? client})
    : resolveFile = null,
      _client = client ?? SettingsClient();

  final File Function()? resolveFile;
  final SettingsClient? _client;
  StreamSubscription? _changes;
  RemyaTheme theme = const .new();
  String? error;
  String? _content;
  Timer? _timer;
  bool _loading = false;
  bool _disposed = false;
  String? _seed;

  /// Accent is optional: an older service or a missing file keeps the default seed.
  Future<String?> _readSeed(File? themeFile) async {
    try {
      if (_client case final client?) {
        return ThemeConfig.seedFromAccent(await client.call('Get', ['accent']));
      }
      final file = File('${themeFile!.parent.path}/accent.toml');
      return await file.exists()
          ? ThemeConfig.seedFromAccentFile(await file.readAsString())
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> start() async {
    if (_client case final client?) {
      _changes = client.changes.listen(
        (change) {
          if (_disposed) return;
          try {
            if (change.topic == 'theme') {
              _apply(ThemeConfig.fromMap(change.value).withSeed(_seed));
            } else if (change.topic == 'accent') {
              reload();
            } else if (change.topic == 'error') {
              error =
                  change.value['message']?.toString() ??
                  'Settings service error';
              notifyListeners();
            }
          } catch (failure) {
            error = 'Invalid settings update: $failure';
            notifyListeners();
          }
        },
        onError: (Object failure) {
          if (!_disposed) {
            error = '$failure';
            notifyListeners();
          }
        },
      );
    }
    await reload();
    // Atomic replacements and directories created after startup are both seen.
    _timer = Timer.periodic(
      Duration(milliseconds: _client == null ? 500 : 2000),
      (_) => reload(),
    );
  }

  Future<void> reload() async {
    if (_loading || _disposed) return;
    _loading = true;
    final previousError = error;
    var changed = false;
    try {
      ThemeConfig? config;
      File? file;
      if (_client case final client?) {
        config = ThemeConfig.fromMap(await client.call('Get', ['theme']));
      } else {
        file = resolveFile!();
        if (await file.exists()) {
          config = ThemeConfig.parse(await file.readAsString());
        }
      }
      if (config != null) {
        _seed = await _readSeed(file);
        config = config.withSeed(_seed);
        final content = config.toJson();
        if (content != _content) {
          theme = RemyaTheme.fromConfig(config);
          _content = content;
          changed = true;
        }
      }
      error = null;
    } catch (failure) {
      error = 'Could not read the settings theme: $failure';
    } finally {
      _loading = false;
      if (!_disposed && (changed || previousError != error)) notifyListeners();
    }
  }

  void _apply(ThemeConfig config) {
    if (_disposed) return;
    final content = config.toJson();
    if (content == _content && error == null) return;
    theme = RemyaTheme.fromConfig(config);
    _content = content;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _changes?.cancel();
    _client?.close();
    super.dispose();
  }
}
