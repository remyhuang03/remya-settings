import 'package:material_ui/material_ui.dart';

class DefaultApplication {
  const DefaultApplication(this.raw);
  final Map raw;
  String get id => raw['id'] as String;
  String get name => raw['name'] as String;
  String? get icon => raw['icon'] as String?;
  List<String> get types => (raw['types'] as List).cast<String>();
}

class DefaultAppsController extends ChangeNotifier {
  DefaultAppsController({
    required this.read,
    required this.applications,
    required this.searchTypes,
    required this.write,
    required this.resolve,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String) applications;
  final Future<Map<String, dynamic>> Function(String) searchTypes;
  final Future<Map<String, dynamic>> Function(String, String, List<String>)
  write;
  final Future<Map<String, dynamic>> Function(String) resolve;
  Map<String, dynamic> value = {};
  List<DefaultApplication> apps = const [];
  String? errorMessage;
  bool isBusy = false;
  bool _readFailed = false;
  bool get hasConflict => value['conflict'] == true;
  bool get canChange =>
      value['writable'] == true && !_readFailed && !hasConflict && !isBusy;
  List<Map> get groups => (value['groups'] as List? ?? []).cast<Map>();
  Map get system => value['system'] as Map? ?? {};
  Map get saved => value['saved'] as Map? ?? {};
  DefaultApplication? application(String? id) {
    final handler = (value['handlers'] as Map?)?[id];
    return handler is Map
        ? DefaultApplication(handler)
        : apps.where((a) => a.id == id).firstOrNull;
  }

  String name(String? id) {
    if (id == null) return 'Unknown';
    if (id.isEmpty) return 'Not set';
    return application(id)?.name ?? '$id (unavailable)';
  }

  String summary(List<String> types) {
    final values = types.map((t) => system[t] as String?).toSet();
    return values.length == 1 ? name(values.single) : 'Mixed defaults';
  }

  String get conflictSummary => [
    for (final type in saved.keys)
      if (saved[type] != system[type])
        '$type\nSystem: ${name(system[type] as String?)}\nSettings: ${name(saved[type] as String?)}',
  ].join('\n\n');

  Future<void> reload() async {
    try {
      value = await read();
      final result = await applications('');
      apps = [
        for (final raw in result['applications'] as List)
          DefaultApplication(raw as Map),
      ];
      _readFailed = false;
      errorMessage = value['error'] as String?;
    } catch (error) {
      _readFailed = true;
      errorMessage = '$error';
    }
    notifyListeners();
  }

  Future<void> _change(Future<Map<String, dynamic>> Function() action) async {
    if (isBusy) return;
    isBusy = true;
    notifyListeners();
    String? failure;
    try {
      value = await action();
    } catch (error) {
      failure = '$error';
    }
    await reload();
    errorMessage = failure ?? errorMessage;
    isBusy = false;
    notifyListeners();
  }

  Future<void> set(String setting, String application, List<String> types) =>
      _change(() => write(setting, application, types));
  Future<void> useSystemConfiguration() => _change(() => resolve('system'));
  Future<void> applySavedConfiguration() => _change(() => resolve('settings'));
}

class DefaultAppsScope extends InheritedNotifier<DefaultAppsController> {
  const DefaultAppsScope({
    super.key,
    required DefaultAppsController controller,
    required super.child,
  }) : super(notifier: controller);
  static DefaultAppsController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DefaultAppsScope>()?.notifier;
}
