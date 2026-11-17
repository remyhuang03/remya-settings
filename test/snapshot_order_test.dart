import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/bluetooth/application/bluetooth_controller.dart';
import 'package:remya_settings/features/network/application/network_controller.dart';
import 'package:remya_settings/features/sound/application/sound_controller.dart';

void main() {
  const old = <String, dynamic>{'snapshot': 'old'};
  const fresh = <String, dynamic>{'snapshot': 'fresh'};

  test(
    'sound keeps a newer signal over an outstanding read and write',
    () async {
      final read = Completer<Map<String, dynamic>>();
      final write = Completer<Map<String, dynamic>>();
      final controller = SoundController(
        read: () => read.future,
        write: (_, _) => write.future,
      );
      addTearDown(controller.dispose);

      final reloading = controller.reload();
      controller.apply(fresh);
      read.complete(old);
      await reloading;
      expect(controller.value, same(fresh));

      final updating = controller.set('sound.setting', {});
      controller.apply(fresh);
      write.complete(old);
      await updating;
      expect(controller.value, same(fresh));
    },
  );

  test('Bluetooth keeps newer signals and allows overlapping cancel', () async {
    final read = Completer<Map<String, dynamic>>();
    final pair = Completer<Map<String, dynamic>>();
    final cancel = Completer<Map<String, dynamic>>();
    final controller = BluetoothController(
      read: () => read.future,
      write: (id, _) => id == 'bluetooth.pair' ? pair.future : cancel.future,
    );
    addTearDown(controller.dispose);

    final reloading = controller.reload();
    controller.apply(fresh);
    read.complete(old);
    await reloading;
    expect(controller.value, same(fresh));

    final pairing = controller.set('bluetooth.pair');
    final cancelling = controller.set('bluetooth.cancel');
    cancel.complete(fresh);
    await cancelling;
    expect(controller.sending, isTrue);
    pair.complete(old);
    await pairing;
    expect(controller.sending, isFalse);
    expect(controller.value, same(fresh));
  });

  test('network retains a newer signal during the write readback', () async {
    final firstRead = Completer<Map<String, dynamic>>();
    final readback = Completer<Map<String, dynamic>>();
    final readbackStarted = Completer<void>();
    var calls = 0;
    final controller = NetworkController(
      read: () {
        if (calls++ == 0) return firstRead.future;
        readbackStarted.complete();
        return readback.future;
      },
      write: (_, _) async => old,
      resolve: (_) async => old,
      formatDate: (value) async => value,
      readTraffic: () async => {},
    );
    addTearDown(controller.dispose);

    final reloading = controller.reload();
    controller.apply(fresh);
    firstRead.complete(old);
    await reloading;
    expect(controller.value, same(fresh));

    final updating = controller.set('network.setting', 'value');
    await readbackStarted.future;
    controller.apply(fresh);
    readback.complete(old);
    await updating;
    expect(controller.value, same(fresh));
  });
}
