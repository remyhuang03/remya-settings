import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

import '../data/date_time_backend.dart';

const timezoneSettingId = 'date-time.fb2a23dc';
const manualTimeSettingId = 'date-time.6422d209';
const automaticTimeSettingId = 'date-time.db451de3';
const syncNowSettingId = 'date-time.098d06ec';
const timeServerSettingId = 'date-time.7e33a213';
const dateTimeSettingIds = {
  timezoneSettingId,
  manualTimeSettingId,
  automaticTimeSettingId,
  syncNowSettingId,
  timeServerSettingId,
};

abstract class DateTimeController extends ChangeNotifier {
  DateTimeController({required this.backend});
  final DateTimeBackend backend;
  DateTimeState? state;
  List<String> timezones = const [];
  Map<String, String> timezoneLabels = const {};
  String? errorMessage;
  bool isBusy = false;
  bool restartSuggested = false;
  bool restartDeferred = false;
  String? get savedTimezone;
  bool get hasConflict;
  bool get isSyncing;
  bool get hideManualTime;
  Map<String, dynamic> _preferences(DateTimeState value) => {
    'timezone': value.timezone,
    'ntp': value.ntp,
    'time_servers': value.timeServers,
  };
  bool _equal(Object? a, Object? b) =>
      a is List && b is List ? listEquals(a, b) : a == b;

  String get conflictSummary {
    final saved = toMap()['saved'] as Map?;
    if (!hasConflict || state == null || saved == null) return '';
    const labels = {
      'timezone': 'Time zone',
      'ntp': 'Automatic time',
      'time_servers': 'Time servers',
    };
    String format(String key, Object? value) => switch (key) {
      'ntp' => value == true ? 'On' : 'Off',
      'time_servers' =>
        (value as List).isEmpty ? 'Automatic' : value.join(', '),
      _ => '$value',
    };
    return _preferences(state!).entries
        .where(
          (entry) =>
              saved.containsKey(entry.key) &&
              !(entry.key == 'time_servers' && state!.syncError != null) &&
              !_equal(entry.value, saved[entry.key]),
        )
        .map(
          (entry) =>
              '${labels[entry.key]}\nSystem: ${format(entry.key, entry.value)}\nSettings: ${format(entry.key, saved[entry.key])}',
        )
        .join('\n\n');
  }

  void deferRestart() {
    restartDeferred = true;
    notifyListeners();
  }

  Future<void> reload();
  Future<void> retry();
  Future<void> useSystemConfiguration();
  Future<void> applySavedConfiguration();
  Future<DateTimeState> setTimezone(String timezone);
  Future<DateTimeState> setAutomaticTime(bool enabled);
  Future<DateTimeState> setTimeServers(List<String> servers);
  Future<DateTimeState> syncNow();
  Future<void> restart();
  Future<DateTimeState> setManualTime(String localTime, String timezone);
  Map<String, dynamic> toMap();
}

class DateTimeScope extends InheritedNotifier<DateTimeController> {
  const DateTimeScope({
    super.key,
    required DateTimeController controller,
    required super.child,
  }) : super(notifier: controller);
  static DateTimeController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DateTimeScope>()?.notifier;
}
