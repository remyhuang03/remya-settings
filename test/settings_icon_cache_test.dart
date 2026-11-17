import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/integration/settings_icon_cache.dart';

void main() {
  test(
    'a failed icon lookup shares a short-lived miss and then retries',
    () async {
      var now = DateTime.utc(2026);
      final cache = SettingsIconCache(now: () => now);
      addTearDown(cache.dispose);
      var requests = 0;
      final gate = Completer<Uint8List?>();
      Future<Uint8List?> lookup() {
        if (++requests == 1) return gate.future;
        return Future.value(Uint8List(3));
      }

      final first = cache.get('app', lookup);
      expect(cache.get('app', lookup), same(first));
      gate.completeError(PlatformException(code: 'NotReady'));
      expect(await first, isNull);
      expect(await cache.get('app', lookup), isNull);
      expect(requests, 1);
      now = now.add(const Duration(seconds: 10));
      expect(await cache.get('app', lookup), hasLength(3));
      expect(requests, 2);
    },
  );

  test(
    'a theme invalidation rejects old loads and the byte limit evicts LRU',
    () async {
      final cache = SettingsIconCache(maxBytes: 6);
      addTearDown(cache.dispose);
      final gate = Completer<Uint8List?>();
      final old = cache.get('app', () => gate.future);
      cache.invalidate();
      Future<Uint8List?> icon() async => Uint8List(3);
      final app = cache.get('app', icon);
      await app;
      gate.complete(Uint8List(4));
      expect(await old, isNull);
      final first = cache.get('first', icon);
      await first;
      expect(cache.get('app', icon), same(app));
      await cache.get('second', icon);
      final firstAgain = cache.get('first', icon);
      expect(firstAgain, isNot(same(first)));
      expect(cache.get('app', icon), same(app));
      await firstAgain;
    },
  );
}
