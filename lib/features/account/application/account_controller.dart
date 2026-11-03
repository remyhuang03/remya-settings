import 'package:material_ui/material_ui.dart';

class AccountController extends ChangeNotifier {
  AccountController({required this.read, required this.save});
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String, Map<String, double>) save;
  Map<String, dynamic> value = {};
  String? errorMessage;
  bool isBusy = false;
  bool _disposed = false;

  Future<void> reload() async {
    try {
      final next = await read();
      if (_disposed) return;
      value = next;
      errorMessage = value['error'] as String?;
    } catch (error) {
      if (_disposed) return;
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<void> saveAvatar(String path, Map<String, double> crop) async {
    if (isBusy) return;
    isBusy = true;
    notifyListeners();
    try {
      final next = await save(path, crop);
      if (_disposed) return;
      value = next;
      errorMessage = value['error'] as String?;
    } catch (error) {
      if (_disposed) return;
      errorMessage = '$error';
    } finally {
      isBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
