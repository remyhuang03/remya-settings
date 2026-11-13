class DateTimeState {
  const DateTimeState({
    required this.unixMicros,
    required this.localTime,
    required this.timezone,
    required this.ntp,
    required this.ntpSynchronized,
    required this.timeServers,
    required this.activeTimeServer,
    this.syncError,
  });
  final int unixMicros;
  final String localTime;
  final String timezone;
  final bool ntp;
  final bool ntpSynchronized;
  final List<String> timeServers;
  final String activeTimeServer;
  final String? syncError;
}

class TimezoneOption {
  const TimezoneOption({required this.id, required this.label});
  final String id;
  final String label;
}

abstract interface class DateTimeBackend {
  Future<DateTimeState> read();
  Future<List<TimezoneOption>> timezones();
  Future<DateTimeState> setTimezone(String timezone);
  Future<DateTimeState> setManualTime(String localTime, String timezone);
  Future<DateTimeState> setAutomaticTime(bool enabled);
  Future<DateTimeState> setTimeServers(List<String> servers);
  Future<DateTimeState> syncNow();
  Future<void> restart();
}
