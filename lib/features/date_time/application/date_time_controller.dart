import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:toml/toml.dart';

import '../../integration/settings_file.dart';
import '../data/date_time_backend.dart';

const timezoneSettingId = 'date-time.fb2a23dc';
const manualTimeSettingId = 'date-time.6422d209';
const automaticTimeSettingId = 'date-time.db451de3';
const syncNowSettingId = 'date-time.098d06ec';
const timeServerSettingId = 'date-time.7e33a213';
const timeLocaleSettingId = 'date-time.format';
const dateTimeSettingIds = {
  timezoneSettingId,
  manualTimeSettingId,
  automaticTimeSettingId,
  syncNowSettingId,
  timeServerSettingId,
  timeLocaleSettingId,
};

class DateTimeController extends ChangeNotifier {
  DateTimeController({required this.backend, required this.file});
  final DateTimeBackend backend;
  final File file;
  DateTimeState? state;
  List<String> timezones = const [];
  Map<String, String> timezoneLabels = const {};
  List<String> timeLocales = const [];
  Map<String, dynamic>? _saved;
  String? get savedTimezone => _saved?['timezone'] as String?;
  String? errorMessage;
  bool isBusy = false;
  bool _syncing = false;
  bool get isSyncing => _syncing;
  bool _enablingAutomaticTime = false;
  bool get hideManualTime => state?.ntp == true || _enablingAutomaticTime;
  bool restartSuggested = false;
  bool restartDeferred = false;
  bool _disposed = false;
  Future<void> _pending = Future.value();
  Map<String, dynamic> _preferences(DateTimeState value) => {
    'timezone': value.timezone,
    'ntp': value.ntp,
    'time_servers': value.timeServers,
    'time_locale': value.timeLocale,
  };
  bool get hasConflict =>
      state != null &&
      _saved != null &&
      _preferences(state!).entries.any(
        (entry) => entry.key == 'time_servers' && state!.syncError != null
            ? false
            : !_equal(entry.value, _saved![entry.key]),
      );
  bool _equal(Object? a, Object? b) =>
      a is List && b is List ? listEquals(a, b) : a == b;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _run<T>(Future<T> Function() operation, {bool background = false}) {
    final result = _pending.then((_) async {
      if (!background) {
        isBusy = true;
        _notify();
      }
      try {
        final result = await operation();
        errorMessage = null;
        return result;
      } catch (error) {
        errorMessage = '$error';
        rethrow;
      } finally {
        if (!background) isBusy = false;
        _notify();
      }
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Map<String, dynamic>> _load(DateTimeState observed) async {
    if (!await file.exists()) return _preferences(observed);
    final map = TomlDocument.parse(await file.readAsString()).toMap();
    if (map['version'] != 1 ||
        map.keys.any(
          (key) => !{
            'version',
            'timezone',
            'ntp',
            'time_servers',
            'time_locale',
          }.contains(key),
        ) ||
        !timezones.contains(map['timezone']) ||
        (map.containsKey('ntp') && map['ntp'] is! bool) ||
        (map.containsKey('time_locale') &&
            !timeLocales.contains(map['time_locale'])) ||
        (map.containsKey('time_servers') &&
            (map['time_servers'] is! List ||
                (map['time_servers'] as List).any((v) => v is! String)))) {
      throw const FormatException('Invalid date/time configuration');
    }
    final saved = {..._preferences(observed), ...map}..remove('version');
    _validateServers((saved['time_servers'] as List).cast<String>());
    return saved;
  }

  Future<void> _save(Map<String, dynamic> values) async {
    await writeSettingsFile(
      file,
      '${TomlDocument.fromMap({'version': 1, ...values})}\n',
    );
    _saved = values;
  }

  Future<DateTimeState> _accept(
    DateTimeState observed,
    List<String> keys,
  ) async {
    state = observed;
    final values = _preferences(observed);
    await _save({...?_saved, for (final key in keys) key: values[key]});
    return observed;
  }

  Future<void> retry() => reload();

  Future<void> reload() => _run(() async {
    final observed = await backend.read();
    // Refresh offsets too: daylight-saving changes must not leave stale GMT labels.
    final zones = await backend.timezones();
    timezones = List.unmodifiable(zones.map((zone) => zone.id));
    timezoneLabels = {for (final zone in zones) zone.id: zone.label};
    if (!timezones.contains(observed.timezone)) {
      throw StateError('Unknown system time zone');
    }
    if (timeLocales.isEmpty) {
      timeLocales = List.unmodifiable(await backend.timeLocales());
    }
    final saved = await _load(observed);
    if (!await file.exists()) await _save(saved);
    _saved = saved;
    state = observed;
  }, background: true);
  Future<void> useSystemConfiguration() => _run(() async {
    final observed = await backend.read();
    if (!timezones.contains(observed.timezone) ||
        !timeLocales.contains(observed.timeLocale)) {
      throw StateError('Unknown system date/time configuration');
    }
    await _save(_preferences(observed));
    state = observed;
  });
  Future<void> applySavedConfiguration() => _run(() async {
    final saved = Map<String, dynamic>.from(_saved!);
    var observed = await backend.read();
    if (observed.timezone != saved['timezone']) {
      observed = await backend.setTimezone(saved['timezone'] as String);
    }
    if (observed.timeLocale != saved['time_locale']) {
      observed = await backend.setTimeLocale(saved['time_locale'] as String);
      restartSuggested = true;
      restartDeferred = false;
    }
    final servers = (saved['time_servers'] as List).cast<String>();
    if (!_equal(observed.timeServers, servers)) {
      if (!observed.ntp) observed = await backend.setAutomaticTime(true);
      observed = await backend.setTimeServers(servers);
    }
    if (observed.ntp != saved['ntp']) {
      observed = await backend.setAutomaticTime(saved['ntp'] as bool);
    }
    state = observed;
    if (hasConflict) {
      throw StateError('Date/time readback does not match saved settings');
    }
  });
  Future<DateTimeState> setTimezone(String timezone) => _run(() async {
    if (!timezones.contains(timezone)) {
      throw ArgumentError('Choose a time zone from the system list');
    }
    final observed = await backend.setTimezone(timezone);
    if (observed.timezone != timezone) {
      throw StateError('Time zone readback does not match the request');
    }
    return _accept(observed, ['timezone']);
  });
  Future<DateTimeState> setAutomaticTime(bool enabled) => _run(() async {
    _enablingAutomaticTime = enabled;
    _notify();
    try {
      final observed = await backend.setAutomaticTime(enabled);
      if (observed.ntp != enabled) {
        throw StateError('Automatic time readback does not match the request');
      }
      return await _accept(observed, ['ntp']);
    } finally {
      _enablingAutomaticTime = false;
    }
  });
  void _validateServers(List<String> servers) {
    if (servers.length > 16 ||
        servers.any(
          (server) =>
              InternetAddress.tryParse(server) == null &&
              (server.length > 253 ||
                  server
                      .replaceFirst(RegExp(r'\.$'), '')
                      .split('.')
                      .any(
                        (label) =>
                            label.length > 63 ||
                            !RegExp(
                              r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$',
                            ).hasMatch(label),
                      )),
        )) {
      throw ArgumentError(
        'Use up to 16 NTP host names or IP addresses, without URLs or ports',
      );
    }
  }

  Future<DateTimeState> setTimeServers(List<String> servers) => _run(() async {
    _validateServers(servers);
    final observed = await backend.setTimeServers(servers);
    if (!_equal(observed.timeServers, servers)) {
      throw StateError('Time server readback does not match the request');
    }
    return _accept(observed, ['time_servers']);
  });
  Future<DateTimeState> syncNow() => _run(() async {
    _syncing = true;
    _notify();
    try {
      final observed = await backend.syncNow();
      state = observed;
      if (!observed.ntp || !observed.ntpSynchronized) {
        throw StateError('Clock synchronization was not confirmed');
      }
      return observed;
    } finally {
      _syncing = false;
    }
  });
  Future<DateTimeState> setTimeLocale(String locale) => _run(() async {
    if (!timeLocales.contains(locale)) {
      throw ArgumentError('Choose an installed locale');
    }
    final previous = state?.timeLocale;
    final observed = await backend.setTimeLocale(locale);
    if (observed.timeLocale != locale) {
      throw StateError('LC_TIME readback does not match the request');
    }
    if (previous != locale) {
      restartSuggested = true;
      restartDeferred = false;
    }
    return _accept(observed, ['time_locale']);
  });
  void deferRestart() {
    restartDeferred = true;
    _notify();
  }

  Future<void> restart() => _run(backend.restart);
  Future<DateTimeState> setManualTime(
    String localTime,
    String timezone,
  ) => _run(() async {
    final parsed = DateTime.tryParse(localTime);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$').hasMatch(localTime) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 19) != localTime ||
        !timezones.contains(timezone)) {
      throw ArgumentError('Use a valid local date/time and a system time zone');
    }
    return _accept(await backend.setManualTime(localTime, timezone), ['ntp']);
  });
  Map<String, dynamic> toMap() => {
    if (state case final value?) ...{
      'unix_micros': value.unixMicros.toString(),
      'local_time': value.localTime,
      ..._preferences(value),
      'ntp_synchronized': value.ntpSynchronized,
      'active_time_server': value.activeTimeServer,
      'sync_error': value.syncError,
    },
    'saved_timezone': savedTimezone,
    'saved': _saved,
    'conflict': hasConflict,
    'restart_suggested': restartSuggested,
  };
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
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
