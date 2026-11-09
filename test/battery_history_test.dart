import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/power/domain/battery_history.dart';

Map<String, dynamic> event(int id, int time, String kind, Object value) => {
  'id': id,
  'time': time,
  'kind': kind,
  'value': value,
};
void main() {
  test('sleep and screen durations remain separate', () {
    final h = BatteryHistory(
      [
        event(1, 0, 'state', 'screen-on'),
        event(2, 60, 'state', 'screen-off'),
        event(3, 120, 'state', 'sleep'),
        event(4, 420, 'state', 'screen-on'),
        event(5, 480, 'battery', {'percentage': 50}),
      ],
      0,
      480,
    );
    expect(h.durations, {'screen-on': 120, 'screen-off': 60, 'sleep': 300});
    expect(h.unknown, 0);
    expect(h.points.single.percent, 50);
  });
  test('unobserved intervals and service restarts are not sleep', () {
    final h = BatteryHistory(
      [
        event(1, 0, 'state', 'sleep'),
        event(2, 500, 'session', 'start'),
        event(3, 500, 'state', 'screen-on'),
        event(4, 560, 'battery', {'percentage': 40}),
      ],
      0,
      560,
    );
    expect(h.durations['sleep'], 0);
    expect(h.durations['screen-on'], 60);
    expect(h.unknown, 500);
  });
  test('range context is clipped to the chosen interval', () {
    final h = BatteryHistory(
      [
        event(1, 0, 'state', 'sleep'),
        event(2, 300, 'state', 'screen-off'),
        event(3, 360, 'battery', {'percentage': 70}),
      ],
      120,
      360,
    );
    expect(h.durations['sleep'], 180);
    expect(h.durations['screen-off'], 60);
    expect(h.unknown, 0);
  });
  test('drain skips charging and gaps; plugged-in stretches merge', () {
    Map<String, Object> b(num p, bool plugged) => {
      'percentage': p,
      'on_battery': !plugged,
    };
    final h = BatteryHistory(
      [
        event(1, 0, 'battery', b(80, false)),
        event(2, 60, 'battery', b(78, false)),
        event(3, 120, 'battery', b(79, true)),
        event(4, 180, 'battery', b(85, true)),
        event(5, 240, 'battery', b(84, false)),
        event(6, 1000, 'battery', b(70, false)),
        event(7, 1060, 'battery', b(69, false)),
      ],
      0,
      1060,
    );
    expect(h.drained, 4);
    expect(h.pluggedRanges, [(120, 240)]);
  });
}
