import 'package:material_ui/material_ui.dart';

import 'appimages_controller.dart';

export 'appimages_controller.dart';

class InstalledApplication {
  const InstalledApplication(this.raw);
  final Map raw;
  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  String? get icon => raw['icon'] as String?;
  String get source => raw['source'] as String;
  String? get version => raw['version'] as String?;
  int? get size => raw['size'] as int?;
  int? get installed => raw['installed'] as int?;
  String get token => raw['token'] as String;
  String get reason => raw['reason'] as String;
  bool get canUninstall => raw['uninstallable'] == true;
}

class ApplicationsController extends ChangeNotifier {
  ApplicationsController({
    required this.read,
    required this.remove,
    required this.formatDate,
    required this.readExternalTools,
    required this.openExternalTool,
    this.appImages,
  });
  final AppImagesController? appImages;
  final Future<Map<String, dynamic>> Function() read;
  final Future<String> Function(String) formatDate;
  final Future<Map<String, dynamic>> Function(String) readExternalTools;
  final Future<Map<String, dynamic>> Function(String) openExternalTool;
  final Future<Map<String, dynamic>> Function(String, String) remove;
  List<InstalledApplication> applications = const [];
  List<String> warnings = const [];
  String? errorMessage;
  bool isBusy = false;
  bool loaded = false;

  Future<void> reload() async {
    try {
      final state = await read();
      applications = [
        for (final raw in state['applications'] as List)
          InstalledApplication(raw as Map),
      ];
      warnings = (state['warnings'] as List).cast<String>();
      errorMessage = null;
      loaded = true;
    } catch (error) {
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<void> uninstall(InstalledApplication app) async {
    if (isBusy) return;
    isBusy = true;
    notifyListeners();
    String? failure;
    try {
      await remove(app.id, app.token);
    } catch (error) {
      failure = '$error';
    }
    await reload();
    errorMessage = failure ?? errorMessage;
    isBusy = false;
    notifyListeners();
  }
}

class ApplicationsScope extends InheritedNotifier<ApplicationsController> {
  const ApplicationsScope({
    super.key,
    required ApplicationsController controller,
    required super.child,
  }) : super(notifier: controller);
  static ApplicationsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ApplicationsScope>()?.notifier;
}
