import 'package:material_ui/material_ui.dart';

const nightLightEnabledId = 'night-light.e32be03e';
const nightLightTemperatureId = 'night-light.temperature';
const nightLightScheduleId = 'night-light.7e6239c9';
const nightLightTimingId = 'night-light.50840111';
const nightLightStartId = 'night-light.e8868af6';
const nightLightEndId = 'night-light.a0bb9f49';

class NightLightController extends ChangeNotifier {
  NightLightController({
    required this.read,
    required this.write,
    required this.resolve,
  });
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String, String) write;
  final Future<Map<String, dynamic>> Function(String) resolve;
  Map<String, dynamic> value = {};
  String? errorMessage;
  bool isBusy = false;
  bool _readFailed = false;

  bool get isLoaded => value.isNotEmpty;
  bool get hasConflict => value['conflict'] == true;
  bool get isRunning => value['running'] == true;
  bool get isEnabled => value['enabled'] == true;
  bool get hasSchedule => value['schedule'] == true;
  int get temperature => (value['temperature'] as num?)?.toInt() ?? 6000;
  String get start => value['start'] as String? ?? '';
  String get end => value['end'] as String? ?? '';
  String? get writeBlocked => value['write_blocked'] as String?;
  bool get canChange =>
      isLoaded &&
      !_readFailed &&
      !hasConflict &&
      writeBlocked == null &&
      !isBusy;

  static String _describe(Map? prefs) {
    if (prefs == null) return 'Unknown';
    final schedule = prefs['start'] == null
        ? prefs['enabled'] == true
              ? 'on'
              : 'off'
        : '${prefs['start']} to ${prefs['end']}';
    return '${prefs['temperature']} K, $schedule';
  }

  String get conflictSummary =>
      'System: ${_describe(value['system'] as Map?)}\n'
      'Settings: ${_describe(value['saved'] as Map?)}';

  void apply(Map<String, dynamic> next) {
    value = next;
    errorMessage = next['error'] as String?;
    _readFailed = false;
    notifyListeners();
  }

  Future<void> reload() async {
    try {
      apply(await read());
    } catch (error) {
      _readFailed = true;
      errorMessage = '$error';
      notifyListeners();
    }
  }

  Future<void> _change(Future<Map<String, dynamic>> Function() action) async {
    if (isBusy) return;
    isBusy = true;
    notifyListeners();
    String? failure;
    try {
      await action();
    } catch (error) {
      failure = '$error';
    }
    await reload();
    errorMessage = failure ?? errorMessage;
    isBusy = false;
    notifyListeners();
  }

  Future<void> set(String id, String next) => _change(() => write(id, next));
  Future<void> useSystemConfiguration() => _change(() => resolve('system'));
  Future<void> applySavedConfiguration() => _change(() => resolve('settings'));
}

class NightLightScope extends InheritedNotifier<NightLightController> {
  const NightLightScope({
    super.key,
    required NightLightController controller,
    required super.child,
  }) : super(notifier: controller);
  static NightLightController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NightLightScope>()?.notifier;
}
