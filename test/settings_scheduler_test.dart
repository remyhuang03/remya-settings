import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/integration/settings_scheduler.dart';

void main() {
  test('runs independent checks concurrently, coalesces rounds and isolates failure', () async {
    final gate = Completer<void>();
    var first = 0;
    var second = 0;
    final scheduler = SettingsScheduler([
      () async {
        first++;
        await gate.future;
        throw StateError('one backend failed');
      },
      () async {
        second++;
        await gate.future;
      },
    ]);
    final round = scheduler.refresh();
    expect(identical(round, scheduler.refresh()), isTrue);
    expect(first, 1);
    expect(second, 1);
    gate.complete();
    await round;
    await scheduler.refresh();
    expect(first, 2);
    expect(second, 2);
    scheduler.dispose();
    await scheduler.refresh();
    expect(first, 2);
  });
}
