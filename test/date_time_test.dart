import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings/features/date_time/application/date_time_controller.dart';

import 'support/fake_date_time.dart';

void main() {
  late Directory directory;
  late FakeDateTimeBackend backend;
  late DateTimeController controller;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('remya-datetime-');
    backend = FakeDateTimeBackend();
    controller = DateTimeController(
      backend: backend,
      file: File('${directory.path}/date-time.toml'),
    );
  });
  tearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });

  test('initialization adopts the system, caches options, and retains both sides of conflicts', () async {
    await controller.reload();
    expect(controller.savedTimezone, 'Asia/Taipei');
    expect(backend.writes, 0);
    expect(controller.file.readAsStringSync(), contains('Asia/Taipei'));
    backend.timezone = 'UTC';
    await controller.reload();
    expect(backend.lists, 2);
    expect(controller.hasConflict, isTrue);
    expect(controller.savedTimezone, 'Asia/Taipei');
    await controller.useSystemConfiguration();
    expect(controller.hasConflict, isFalse);
    expect(controller.savedTimezone, 'UTC');
    backend.timezone = 'Europe/London';
    await controller.reload();
    await controller.setTimezone(controller.savedTimezone!);
    expect(backend.timezone, 'UTC');
    expect(controller.hasConflict, isFalse);
  });

  test(
    'invalid input and failures preserve configuration and surface errors',
    () async {
      backend.error = StateError('timedated unavailable');
      await expectLater(controller.reload(), throwsStateError);
      expect(controller.file.existsSync(), isFalse);
      backend.error = null;
      await controller.reload();
      final before = controller.file.readAsStringSync();
      await expectLater(
        controller.setTimezone('Not/AZone'),
        throwsArgumentError,
      );
      for (final value in [
        '2026-02-30T12:00:00',
        '2026-10-30T24:00:00',
        'invalid',
      ]) {
        await expectLater(
          controller.setManualTime(value, 'Asia/Taipei'),
          throwsArgumentError,
        );
      }
      expect(backend.writes, 0);
      backend.timezone = 'UTC';
      await controller.reload();
      backend.error = StateError('Permission denied');
      await expectLater(
        controller.setTimezone('Asia/Taipei'),
        throwsStateError,
      );
      expect(controller.errorMessage, contains('Permission denied'));
      expect(controller.hasConflict, isTrue);
      expect(controller.file.readAsStringSync(), before);
      backend.error = null;
      controller.file.writeAsStringSync('invalid [');
      await expectLater(controller.reload(), throwsA(isA<FormatException>()));
      expect(controller.savedTimezone, 'Asia/Taipei');
      expect(controller.file.readAsStringSync(), 'invalid [');
    },
  );

  test('manual time is an operation, never a persisted clock target', () async {
    await controller.reload();
    await controller.setManualTime('2026-10-30T14:30:00', 'Asia/Taipei');
    expect(backend.lastLocalTime, '2026-10-30T14:30:00');
    expect(controller.state!.ntp, isFalse);
    expect(controller.file.readAsStringSync(), contains('ntp = false'));
    expect(
      controller.file.readAsStringSync(),
      isNot(contains('2026-10-30T14:30:00')),
    );
  });

  test('automatic time and persistent server choices reconcile', () async {
    await controller.reload();
    await controller.setAutomaticTime(false);
    expect(controller.hideManualTime, isFalse);
    await controller.setAutomaticTime(true);
    expect(controller.hideManualTime, isTrue);
    await controller.setTimeServers(['pool.ntp.org']);
    expect(controller.file.readAsStringSync(), contains('pool.ntp.org'));
    await controller.syncNow();
    expect(backend.syncs, 1);
    await controller.setTimeServers([]);
    expect(backend.servers, isEmpty);
    backend.servers = ['time.example.org'];
    await controller.reload();
    expect(controller.hasConflict, isTrue);
    await controller.applySavedConfiguration();
    expect(backend.servers, isEmpty);
    expect(controller.hasConflict, isFalse);
    for (final servers in [
      ['https://bad'],
      ['bad name'],
      ['-bad'],
      List.filled(17, 'ntp.org'),
    ]) {
      await expectLater(
        controller.setTimeServers(servers),
        throwsArgumentError,
      );
    }
    final before = controller.file.readAsStringSync();
    backend.error = StateError('Authorization canceled');
    await expectLater(
      controller.setTimeServers(['time.example.org']),
      throwsStateError,
    );
    expect(controller.file.readAsStringSync(), before);
  });
}
