import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../integration/snapshot_order.dart';

const fontsSearchSettingId = 'fonts.65a8477b';
const fontsInstallSettingId = 'fonts.158ba0bb';
const fontsDetailsSettingId = 'fonts.fc3969c7';
const fontsUninstallSettingId = 'fonts.f869cae5';
const fontsCompositorFamilySettingId = 'fonts.compositor-family';

class FontFamily {
  const FontFamily(this.raw);
  final Map raw;
  String get name => raw['family'] as String;
  List<String> get styles => (raw['styles'] as List).cast<String>();
  List<String> get formats => (raw['formats'] as List).cast<String>();
  List<String> get files => (raw['files'] as List).cast<String>();
  int get userFiles => raw['user_files'] as int;
  int get systemFiles => raw['system_files'] as int;
  bool get removable => userFiles > 0;
}

class FontsController extends ChangeNotifier {
  FontsController({required this.read, required this.write});
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String id, String value) write;

  List<FontFamily> families = const [];
  String? errorMessage;
  bool loaded = false;
  bool isBusy = false;
  String? _loaded;
  final _snapshots = SnapshotOrder();

  Iterable<FontFamily> matching(String query) {
    final needle = query.trim().toLowerCase();
    return needle.isEmpty
        ? families
        : families.where((f) => f.name.toLowerCase().contains(needle));
  }

  /// Rebuilds only when something changed; the list has hundreds of families.
  Future<void> reload() => isBusy ? Future.value() : _reload();

  Future<void> _reload() async {
    if (_snapshots.disposed) return;
    final current = _snapshots.beginRead();
    final previousError = errorMessage;
    try {
      final state = await read();
      if (!current()) return;
      final encoded = jsonEncode(state['families']);
      errorMessage = null;
      if (encoded != _loaded) {
        families = [
          for (final raw in state['families'] as List) FontFamily(raw as Map),
        ];
        _loaded = encoded;
        loaded = true;
        notifyListeners();
        return;
      }
    } catch (error) {
      if (!current()) return;
      errorMessage = '$error';
    }
    if (errorMessage != previousError) notifyListeners();
  }

  Future<void> _change(Future<void> Function() operation) async {
    if (isBusy || _snapshots.disposed) return;
    _snapshots.invalidate();
    isBusy = true;
    notifyListeners();
    try {
      await operation();
      errorMessage = null;
    } catch (error) {
      errorMessage = '$error';
    }
    if (_snapshots.disposed) return;
    final failure = errorMessage;
    await _reload();
    if (_snapshots.disposed) return;
    errorMessage = failure ?? errorMessage;
    isBusy = false;
    notifyListeners();
  }

  /// Installs in order; a failure stops there and leaves earlier fonts installed.
  Future<void> install(List<String> paths) => _change(() async {
    for (final path in paths) {
      if (_snapshots.disposed) return;
      await write(fontsInstallSettingId, path);
    }
  });

  Future<void> uninstall(String family) =>
      _change(() => write(fontsUninstallSettingId, family));

  @override
  void dispose() {
    _snapshots.dispose();
    super.dispose();
  }
}

class FontsScope extends InheritedNotifier<FontsController> {
  const FontsScope({
    super.key,
    required FontsController controller,
    required super.child,
  }) : super(notifier: controller);

  static FontsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FontsScope>()?.notifier;
}
