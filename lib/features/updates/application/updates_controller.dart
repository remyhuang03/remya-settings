import 'package:material_ui/material_ui.dart';

class UpdatesController extends ChangeNotifier {
  UpdatesController({required this.read, required this.write});
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String, String) write;
  Map<String, dynamic> value = {};
  String? errorMessage;
  bool pending = false;
  bool _disposed = false;
  int _revision = 0;

  bool get busy => value['busy'] == true;
  bool get workInProgress => value['work_in_progress'] == true;
  bool get available => value['available'] == true;
  bool get authorized => value['authorized'] == true;
  List<Map> get packages => (value['packages'] as List? ?? []).cast<Map>();
  bool get canInstall =>
      value['checked_at'] != null &&
      packages.any((package) => package['held'] != true);
  Map get schedule => value['schedule'] as Map? ?? const {};
  List<String> get output => (value['output'] as List? ?? []).cast<String>();

  void apply(Map<String, dynamic> state) {
    if (_disposed ||
        (state['revision'] as num? ?? 0) < (value['revision'] as num? ?? 0)) {
      return;
    }
    value = state;
    errorMessage = state['error'] as String?;
    notifyListeners();
  }

  Future<void> reload() async {
    final revision = _revision;
    try {
      final state = await read();
      if (revision == _revision) apply(state);
    } catch (error) {
      if (!_disposed) {
        errorMessage = '$error';
        notifyListeners();
      }
    }
  }

  Future<void> set(String id, String request) async {
    if (_disposed || pending) return;
    pending = true;
    _revision++;
    errorMessage = null;
    notifyListeners();
    try {
      apply(await write(id, request));
    } catch (error) {
      if (!_disposed) errorMessage = '$error';
    } finally {
      if (!_disposed) {
        pending = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
