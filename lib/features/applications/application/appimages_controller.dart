import 'package:material_ui/material_ui.dart';

import '../../integration/snapshot_order.dart';

class AppImageEntry {
  const AppImageEntry(this.raw);
  final Map raw;
  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  String? get icon => raw['icon'] as String?;
  String? get version => raw['version'] as String?;
  String get path => raw['path'] as String;
  int get size => raw['size'] as int;
  bool get integrated => raw['integrated'] == true;
  String? get source => raw['source'] as String?;
  String? get sourceOrigin => raw['source_origin'] as String?;
  bool get updates => raw['updates'] == true;
  bool get checked => raw['checked'] == true;
  String? get error => raw['error'] as String?;
  Map? get job => raw['job'] as Map?;
  Map? get available => raw['available'] as Map?;
}

class AppImagesController extends ChangeNotifier {
  AppImagesController({
    required this.read,
    required this.write,
    required this.setSource,
    required this.formatDate,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String, String) write;
  final Future<Map<String, dynamic>> Function(String, String?, bool) setSource;
  final Future<String> Function(String) formatDate;

  List<AppImageEntry> apps = const [];
  List<String> installing = const [];
  String directory = '';
  bool autoCheck = false;
  bool autoUpdate = false;
  int lastCheck = 0;
  bool loaded = false;
  String? serviceError;
  String? requestError;
  final _snapshots = SnapshotOrder();

  String? get errorMessage => requestError ?? serviceError;
  Iterable<AppImageEntry> get updatable =>
      apps.where((a) => a.available != null && a.job == null);
  bool get checking => apps.any((a) => a.job != null);

  void apply(Map value) {
    if (_snapshots.disposed) return;
    _snapshots.invalidate();
    apps = [for (final raw in value['apps'] as List) AppImageEntry(raw as Map)];
    installing = (value['installing'] as List).cast<String>();
    directory = value['directory'] as String;
    autoCheck = value['auto_check'] == true;
    autoUpdate = value['auto_update'] == true;
    lastCheck = value['last_check'] as int;
    serviceError = value['error'] as String?;
    loaded = true;
    notifyListeners();
  }

  Future<void> reload() async {
    if (_snapshots.disposed) return;
    final current = _snapshots.beginRead();
    try {
      final next = await read();
      if (current()) apply(next);
    } catch (error) {
      if (!current()) return;
      requestError = '$error';
      notifyListeners();
    }
  }

  Future<bool> _attempt(Future<void> Function() action) async {
    if (_snapshots.disposed) return false;
    _snapshots.invalidate();
    requestError = null;
    try {
      await action();
      await reload();
      return true;
    } catch (error) {
      await reload();
      if (_snapshots.disposed) return false;
      requestError = '$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> run(String id, String value) => _attempt(() => write(id, value));
  Future<bool> saveSource(AppImageEntry app, String? source, bool updates) =>
      _attempt(() => setSource(app.id, source, updates));

  @override
  void dispose() {
    _snapshots.dispose();
    super.dispose();
  }
}
