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

  /// The root updater is installed and every required tool exists.
  bool get available => value['available'] == true;

  /// Checks need only the tools; installing also needs the root updater.
  bool get canCheck => (value['missing'] as List? ?? const []).isEmpty;
  List<Map> get packages => (value['packages'] as List? ?? []).cast<Map>();
  List<Map> get repository =>
      packages.where((package) => package['source'] == 'repository').toList();
  List<Map> get aur =>
      packages.where((package) => package['source'] == 'AUR').toList();
  bool get canInstall =>
      available && value['checked_at'] != null && value['eligible'] == true;
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
