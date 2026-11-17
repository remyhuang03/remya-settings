import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const settingsIconChannel = MethodChannel('top.remya.paths');

final settingsIcons = SettingsIconCache().._watchTheme();

/// Shares GTK icon lookups across rows and bounds retained PNG data.
class SettingsIconCache extends ChangeNotifier {
  SettingsIconCache({this.now = DateTime.now, this.maxBytes = 8 * 1024 * 1024});

  final DateTime Function() now;
  final int maxBytes;
  final _pending = <Object, Future<Uint8List?>>{};
  final _entries =
      <Object, ({Future<Uint8List?> future, int size, DateTime? expires})>{};
  int _bytes = 0;
  int _generation = 0;

  void _watchTheme() {
    settingsIconChannel.setMethodCallHandler((call) async {
      if (call.method == 'iconThemeChanged') invalidate();
    });
  }

  Future<Uint8List?> get(
    Object key,
    Future<Uint8List?> Function() lookup, {
    bool fileBacked = false,
  }) {
    if (_entries.remove(key) case final entry?) {
      if (entry.expires == null || now().isBefore(entry.expires!)) {
        _entries[key] = entry;
        return entry.future;
      }
      _bytes -= entry.size;
    }
    return _pending[key] ??= _load(key, lookup, fileBacked, _generation);
  }

  Future<Uint8List?> _load(
    Object key,
    Future<Uint8List?> Function() lookup,
    bool fileBacked,
    int generation,
  ) async {
    Uint8List? bytes;
    try {
      bytes = await Future.sync(lookup);
    } on PlatformException {
      // The GTK lookup can be retried after the miss expires.
    } on MissingPluginException {
      // The desktop plugin is unavailable in widget tests.
    } catch (error) {
      debugPrint('GTK icon lookup: $error');
    }
    if (generation != _generation) return null;
    final request = _pending.remove(key)!;
    final size = bytes?.lengthInBytes ?? 0;
    if (size <= maxBytes) {
      _entries[key] = (
        future: request,
        size: size,
        expires: bytes == null || bytes.isEmpty
            ? now().add(const Duration(seconds: 10))
            : fileBacked
            ? now().add(const Duration(seconds: 30))
            : null,
      );
      _bytes += size;
      while (_bytes > maxBytes || _entries.length > 256) {
        _bytes -= _entries.remove(_entries.keys.first)!.size;
      }
    }
    return bytes == null || bytes.isEmpty ? null : bytes;
  }

  void invalidate() {
    _generation++;
    _entries.clear();
    _pending.clear();
    _bytes = 0;
    notifyListeners();
  }
}
