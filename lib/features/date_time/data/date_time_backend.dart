import '../../../src/rust/date_time_bridge/api.dart' as rust;

export '../../../src/rust/date_time_bridge/api.dart'
    show DateTimeState, TimezoneOption;

abstract interface class DateTimeBackend {
  Future<rust.DateTimeState> read();
  Future<List<rust.TimezoneOption>> timezones();
  Future<rust.DateTimeState> setTimezone(String timezone);
  Future<rust.DateTimeState> setManualTime(String localTime, String timezone);
  Future<rust.DateTimeState> setAutomaticTime(bool enabled);
  Future<rust.DateTimeState> setTimeServers(List<String> servers);
  Future<rust.DateTimeState> syncNow();
  Future<List<String>> timeLocales();
  Future<rust.DateTimeState> setTimeLocale(String locale);
  Future<void> restart();
}
