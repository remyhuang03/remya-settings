import 'dart:io';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../appearance/application/app_preferences_controller.dart';
import '../appearance/data/app_preferences_file.dart';
import '../appearance/data/system_appearance_backend.dart';
import '../appearance/domain/app_preferences.dart';
import '../date_time/application/date_time_controller.dart';
import '../date_time/data/date_time_backend.dart';
import '../display/data/display_backend.dart';

class ServiceAppearanceBackend implements SystemAppearanceBackend {
  ServiceAppearanceBackend(this.client);
  final SettingsClient client;
  @override
  Future<SystemThemeState> read() async {
    final value = await client.call('Get', ['system']);
    return SystemThemeState(
      mode: value['mode'] == null
          ? null
          : SystemThemeMode.values.byName(value['mode'] as String),
      targets: [
        for (final raw in value['targets'] as List)
          ThemeTargetResult(
            name: raw['name'] as String,
            status: ThemeTargetStatus.values.byName(raw['status'] as String),
            detail: raw['detail'] as String,
          ),
      ],
    );
  }

  @override
  Future<SystemThemeState> apply(SystemThemeMode mode) async {
    await client.call('Set', [materialThemeModeSettingId, mode.name]);
    return read();
  }
}

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

class ServicePreferencesController extends AppPreferencesController {
  ServicePreferencesController(this.client)
    : super(
        store: AppPreferencesFile(AppPreferencesFile.resolve()),
        systemAppearance: ServiceAppearanceBackend(client),
      );
  final SettingsClient client;
  AppPreferences _value = const AppPreferences();
  SystemThemeState? _observed;
  bool _busy = false;
  (String, List<String>)? _failedChange;
  @override
  AppPreferences get preferences => _value;
  @override
  SystemThemeState? get systemTheme => _observed;
  @override
  bool get isBusy => _busy;
  @override
  bool get hasConflict =>
      _observed?.mode != null && _value.themeMode != _observed!.mode;
  void reportError(String message) {
    errorMessage = message;
    notifyListeners();
  }

  @override
  Future<void> reload() async {
    try {
      final value = AppPreferences.fromMap(await client.call('Get', ['theme']));
      final observed = await systemAppearance.read();
      final changed =
          value != _value ||
          observed.mode != _observed?.mode ||
          errorMessage != null;
      _value = value;
      _observed = observed;
      errorMessage = null;
      if (changed) notifyListeners();
    } catch (error) {
      errorMessage = '$error';
      notifyListeners();
    }
  }

  Future<void> _change(String method, List<String> args) async {
    _busy = true;
    notifyListeners();
    try {
      await client.call(method, args);
      _failedChange = null;
      await reload();
    } catch (error) {
      _failedChange = (method, List.of(args));
      errorMessage = '$error';
    } finally {
      _busy = false;
      notifyListeners();
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
  Future<void> setStyleVariant(DynamicSchemeVariant value) =>
      _change('Set', [materialStyleSettingId, value.configKey]);
  @override
  Future<void> setThemeMode(SystemThemeMode value) =>
      _change('Set', [materialThemeModeSettingId, value.name]);
  @override
  Future<void> useSystemConfiguration() =>
      _change('Resolve', ['appearance', 'system']);
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
  timeLocale: map['time_locale'] as String,
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
  Future<List<String>> timeLocales() async =>
      ((await client.call('Get', ['time-locales']))['options'] as List)
          .cast<String>();
  @override
  Future<DateTimeState> setTimeLocale(String value) =>
      set(timeLocaleSettingId, value);
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
    : super(
        backend: ServiceDateTimeBackend(client),
        file: File(
          '${AppPreferencesFile.resolve().parent.path}/date-time.toml',
        ),
      );
  final SettingsClient client;
  Map<String, dynamic> _payload = {};
  bool _enabling = false;
  (String, String)? _failedChange;
  String? _activeSetting;
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
    state = _clock(value);
    _payload = value;
    restartSuggested = value['restart_suggested'] == true;
    errorMessage = value['error'] as String?;
    isBusy = _activeSetting != null || value['authorizing'] == true;
    notifyListeners();
  }

  @override
  Future<void> reload() async {
    try {
      if (timezones.isEmpty) {
        final zones = await backend.timezones();
        timezones = zones.map((z) => z.id).toList();
        timezoneLabels = {for (final z in zones) z.id: z.label};
        timeLocales = await backend.timeLocales();
      }
      _update(await client.call('Get', ['date-time']));
    } catch (error) {
      errorMessage = '$error';
      notifyListeners();
    }
  }

  Future<DateTimeState> _change(String id, String value) async {
    _activeSetting = id;
    isBusy = true;
    _enabling = id == automaticTimeSettingId && value == 'true';
    notifyListeners();
    try {
      final result = await client.call('Set', [id, value]);
      _failedChange = null;
      _update(result);
      return state!;
    } catch (error) {
      _failedChange = (id, value);
      errorMessage = '$error';
      rethrow;
    } finally {
      _activeSetting = null;
      isBusy = _payload['authorizing'] == true;
      _enabling = false;
      notifyListeners();
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
  Future<DateTimeState> setTimeLocale(String locale) =>
      _change(timeLocaleSettingId, locale);
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
}
