import 'dart:math' as math;

typedef BatteryPoint = ({int time, double percent, bool pluggedIn});

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
          pluggedIn: value['on_battery'] == false,
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
  final points = <BatteryPoint>[];

  /// Samples are a minute apart; a longer silence is a gap, not a slope.
  static const maxStep = 90;

  /// Charge lost while on battery, in percentage points; charging never offsets it.
  double get drained {
    var total = 0.0;
    for (var i = 1; i < points.length; i++) {
      final (a, b) = (points[i - 1], points[i]);
      if (b.time - a.time > maxStep || b.pluggedIn) continue;
      total += math.max(0, a.percent - b.percent);
    }
    return total;
  }

  /// Contiguous plugged-in stretches, as `(start, end)` epoch seconds.
  List<(int, int)> get pluggedRanges {
    final ranges = <(int, int)>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (!point.pluggedIn) continue;
      final next = i + 1 < points.length ? points[i + 1] : null;
      final end = next != null && next.time - point.time <= maxStep
          ? next.time
          : point.time;
      if (ranges.isNotEmpty && ranges.last.$2 >= point.time) {
        ranges.last = (ranges.last.$1, end);
      } else {
        ranges.add((point.time, end));
      }
    }
    return ranges;
  }

  final durations = {'screen-on': 0, 'screen-off': 0, 'sleep': 0};
  int get unknown =>
      math.max(0, to - from - durations.values.fold(0, (a, b) => a + b));
  static String duration(int seconds) =>
      '${seconds ~/ 3600} h ${(seconds % 3600) ~/ 60} min';
}
