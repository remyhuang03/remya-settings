import 'package:remya_settings/features/date_time/data/date_time_backend.dart';

class FakeDateTimeBackend implements DateTimeBackend {
  String timezone = 'Asia/Taipei';
  bool ntp = true;
  List<String> servers = [];
  int syncs = 0;
  int restarts = 0;
  int reads = 0;
  int lists = 0;
  int writes = 0;
  Object? error;
  String? lastLocalTime;
  final zones = ['Asia/Taipei', 'Europe/London', 'UTC'];

  @override
  Future<DateTimeState> read() async {
    reads++;
    if (error != null) throw error!;
    return DateTimeState(
      unixMicros: DateTime.now().microsecondsSinceEpoch,
      localTime: '2026-10-30T12:34:56',
      timezone: timezone,
      ntp: ntp,
      ntpSynchronized: ntp,
      timeServers: servers,
      activeTimeServer: servers.firstOrNull ?? 'pool.ntp.org',
      syncError: null,
    );
  }

  @override
  Future<List<TimezoneOption>> timezones() async {
    lists++;
    return [
      for (final zone in zones)
        TimezoneOption(
          id: zone,
          label: '$zone (GMT${zone == 'Asia/Taipei' ? '+08:00' : '+00:00'})',
        ),
    ];
  }

  @override
  Future<DateTimeState> setAutomaticTime(bool enabled) async {
    if (error != null) throw error!;
    writes++;
    ntp = enabled;
    return read();
  }

  @override
  Future<DateTimeState> setTimeServers(List<String> values) async {
    if (error != null) throw error!;
    writes++;
    servers = values;
    return read();
  }

  @override
  Future<DateTimeState> syncNow() async {
    if (error != null) throw error!;
    syncs++;
    return read();
  }

  @override
  Future<void> restart() async {
    if (error != null) throw error!;
    restarts++;
  }

  @override
  Future<DateTimeState> setTimezone(String value) async {
    if (error != null) throw error!;
    writes++;
    timezone = value;
    return read();
  }

  @override
  Future<DateTimeState> setManualTime(String localTime, String zone) async {
    if (error != null) throw error!;
    writes++;
    lastLocalTime = localTime;
    ntp = false;
    return read();
  }
}
