import 'dart:async';
import 'dart:convert';

import 'package:remya_client/remya_client.dart';

import '../date_time/application/date_time_controller.dart';
import '../date_time/data/date_time_backend.dart';
import '../display/data/display_backend.dart';

class ServiceDisplayBackend implements DisplayBackend {
  ServiceDisplayBackend(this.client);
  final SettingsClient client;
  @override
  Future<Map<String, dynamic>> read() => client.call('Get', ['display']);
  @override
  Future<Map<String, dynamic>> brightness() =>
      client.call('Get', ['display-brightness']);
  @override
  Future<Map<String, dynamic>> set(String id, String value) =>
      client.call('Set', [id, value]);
  @override
  Future<Map<String, dynamic>> resolve(String source) =>
      client.call('Resolve', ['display', source]);
}

DateTimeState _clock(Map<String, dynamic> map) => DateTimeState(
  unixMicros: int.parse(map['unix_micros'] as String),
  localTime: map['local_time'] as String,
  timezone: map['timezone'] as String,
  ntp: map['ntp'] as bool,
  ntpSynchronized: map['ntp_synchronized'] as bool,
  timeServers: (map['time_servers'] as List).cast<String>(),
  activeTimeServer: map['active_time_server'] as String,
  syncError: map['sync_error'] as String?,
);

class ServiceDateTimeBackend implements DateTimeBackend {
  ServiceDateTimeBackend(this.client);
  final SettingsClient client;
  @override
  Future<DateTimeState> read() async =>
      _clock(await client.call('Get', ['date-time']));
  @override
  Future<List<TimezoneOption>> timezones() async {
    final value = await client.call('Get', ['timezones']);
    return [
      for (final zone in value['options'] as List)
        TimezoneOption(
          id: zone as String,
          label: (value['labels'] as Map)[zone] as String,
        ),
    ];
  }

  Future<DateTimeState> set(String id, String value) async =>
      _clock(await client.call('Set', [id, value]));
  @override
  Future<DateTimeState> setTimezone(String value) =>
      set(timezoneSettingId, value);
  @override
  Future<DateTimeState> setAutomaticTime(bool enabled) =>
      set(automaticTimeSettingId, '$enabled');
  @override
  Future<DateTimeState> setTimeServers(List<String> servers) =>
      set(timeServerSettingId, jsonEncode(servers));
  @override
  Future<DateTimeState> syncNow() => set(syncNowSettingId, 'sync');
  @override
  Future<void> restart() async {
    await client.call('Restart');
  }

  @override
  Future<DateTimeState> setManualTime(String localTime, String timezone) => set(
    manualTimeSettingId,
    jsonEncode({'local_time': localTime, 'timezone': timezone}),
  );
}

class ServiceDateTimeController extends DateTimeController {
  ServiceDateTimeController(this.client)
    : super(backend: ServiceDateTimeBackend(client));
  final SettingsClient client;
  Map<String, dynamic> _payload = {};
  bool _enabling = false;
  (String, String)? _failedChange;
  String? _activeSetting;
  int _readGeneration = 0;
  bool _reread = false;
  bool _disposed = false;
  @override
  bool get isSyncing => _activeSetting == syncNowSettingId;
  @override
  bool get hideManualTime => state?.ntp == true || _enabling;
  @override
  String? get savedTimezone => _payload['saved_timezone'] as String?;
  @override
  bool get hasConflict => _payload['conflict'] == true;
  @override
  Map<String, dynamic> toMap() => _payload;
  void _update(Map<String, dynamic> value) {
    final next = _clock(value);
    final error = value['error'] as String?;
    state = next;
    _payload = value;
    restartSuggested = value['restart_suggested'] == true;
    errorMessage = error;
    isBusy = _activeSetting != null || value['authorizing'] == true;
    notifyListeners();
  }

  @override
  Future<void> reload() async {
    if (_disposed) return;
    if (_activeSetting != null) {
      _reread = true;
      return;
    }
    final generation = ++_readGeneration;
    bool current() => !_disposed && generation == _readGeneration;
    try {
      if (timezones.isEmpty) {
        final zones = await backend.timezones();
        if (!current()) return;
        timezones = zones.map((z) => z.id).toList();
        timezoneLabels = {for (final z in zones) z.id: z.label};
      }
      final snapshot = await client.call('Get', ['date-time']);
      if (current()) _update(snapshot);
    } catch (error) {
      if (!current()) return;
      errorMessage = '$error';
      notifyListeners();
    }
  }

  Future<DateTimeState> _change(String id, String value) async {
    if (_disposed || isBusy) throw StateError('Date and time is busy');
    _readGeneration++;
    _activeSetting = id;
    isBusy = true;
    _enabling = id == automaticTimeSettingId && value == 'true';
    notifyListeners();
    try {
      final result = await client.call('Set', [id, value]);
      if (_disposed) return _clock(result);
      _failedChange = null;
      _update(result);
      return state!;
    } catch (error) {
      if (_disposed) rethrow;
      _failedChange = (id, value);
      errorMessage = '$error';
      rethrow;
    } finally {
      _activeSetting = null;
      isBusy = _payload['authorizing'] == true;
      _enabling = false;
      if (!_disposed) {
        notifyListeners();
        if (_reread && _failedChange == null) unawaited(reload());
      }
      _reread = false;
    }
  }

  @override
  Future<void> retry() async {
    if (isBusy) return;
    final failed = _failedChange;
    if (failed == null) {
      await reload();
    } else {
      await _change(failed.$1, failed.$2);
    }
  }

  @override
  Future<DateTimeState> setTimezone(String timezone) =>
      _change(timezoneSettingId, timezone);
  @override
  Future<DateTimeState> setAutomaticTime(bool enabled) =>
      _change(automaticTimeSettingId, '$enabled');
  @override
  Future<DateTimeState> setTimeServers(List<String> servers) =>
      _change(timeServerSettingId, jsonEncode(servers));
  @override
  Future<DateTimeState> syncNow() => _change(syncNowSettingId, 'sync');
  @override
  Future<DateTimeState> setManualTime(String localTime, String timezone) =>
      _change(
        manualTimeSettingId,
        jsonEncode({'local_time': localTime, 'timezone': timezone}),
      );
  @override
  Future<void> useSystemConfiguration() async {
    await client.call('Resolve', ['date-time', 'system']);
    await reload();
  }

  @override
  Future<void> applySavedConfiguration() async {
    await client.call('Resolve', ['date-time', 'settings']);
    await reload();
  }

  @override
  Future<void> restart() => backend.restart();

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
