import 'dart:math' as math;

class BatteryHistory {
  BatteryHistory(List<Map<String, dynamic>> observations, this.from, this.to) {
    final events = [...observations]
      ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
    var state = 'unknown';
    for (var i = 0; i < events.length; i++) {
      final event = events[i];
      final time = event['time'] as int;
      final value = event['value'];
      if (event['kind'] == 'session') state = 'unknown';
      if (event['kind'] == 'state') state = value as String;
      if (event['kind'] == 'gap') state = 'unknown';
      if (event['kind'] == 'battery' &&
          value is Map &&
          value['percentage'] is num &&
          time >= from &&
          time <= to) {
        points.add((
          time: time,
          percent: (value['percentage'] as num).toDouble(),
        ));
      }
      final next = i + 1 < events.length ? events[i + 1] : null;
      final end = math.min(to, next?['time'] as int? ?? to);
      final start = math.max(from, time);
      if (end <= start) continue;
      // Awake intervals need regular observations; a stopped service is not screen time.
      var confirmedEnd = state == 'sleep' ? end : math.min(end, time + 90);
      if (state == 'sleep' && next?['kind'] == 'session') confirmedEnd = start;
      if (next?['kind'] == 'gap') {
        confirmedEnd = math.min(
          confirmedEnd,
          (next!['value'] as Map)['from'] as int,
        );
      }
      final seconds = math.max(0, confirmedEnd - start);
      if (durations.containsKey(state)) {
        durations[state] = durations[state]! + seconds;
      }
    }
  }
  final int from;
  final int to;
  final points = <({int time, double percent})>[];
  final durations = {'screen-on': 0, 'screen-off': 0, 'sleep': 0};
  int get unknown =>
      math.max(0, to - from - durations.values.fold(0, (a, b) => a + b));
  static String duration(int seconds) =>
      '${seconds ~/ 3600} h ${(seconds % 3600) ~/ 60} min';
}
