import 'package:material_ui/material_ui.dart';

class CameraController extends ChangeNotifier {
  CameraController({
    required this.read,
    required this.write,
    required this.resolve,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(
    String,
    String,
    int, {
    double? value,
  })
  write;
  final Future<Map<String, dynamic>> Function(String, String) resolve;
  Map<String, dynamic> state = {};
  String? error;
  bool busy = false;
  bool _reading = false;
  bool _disposed = false;
  int _revision = 0;
  List<Map> get devices => (state['devices'] as List? ?? []).cast<Map>();
  bool get available => state['available'] == true;
  bool conflicted(String name) =>
      (state['conflicts'] as List? ?? []).contains(name);
  void apply(Map<String, dynamic> value) {
    if (_disposed) return;
    state = value;
    error = value['error'] as String?;
    notifyListeners();
  }

  Future<void> reload() async {
    if (busy || _reading || _disposed) return;
    _reading = true;
    final revision = _revision;
    try {
      final value = await read();
      if (revision == _revision) apply(value);
    } catch (e) {
      if (!_disposed && revision == _revision) {
        error = '$e';
        notifyListeners();
      }
    } finally {
      _reading = false;
    }
  }

  Future<void> _change(Future<Map<String, dynamic>> Function() action) async {
    if (busy || _disposed) return;
    busy = true;
    _revision++;
    notifyListeners();
    try {
      apply(await action());
    } catch (e) {
      try {
        apply(await read());
      } catch (_) {}
      if (!_disposed) error = '$e';
    } finally {
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> set(Map camera, String field, {double? value}) => _change(
    () => write(
      field,
      camera['name'] as String,
      camera['serial'] as int,
      value: value,
    ),
  );
  Future<void> reconcile(Map camera, String source) =>
      _change(() => resolve(camera['name'] as String, source));
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
