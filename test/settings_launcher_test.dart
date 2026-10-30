import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings_client/settings_contract.dart';

void main() {
  test(
    'debug launcher opens a local executable without an installed service',
    () async {
      final directory = Directory.systemTemp.createTempSync(
        'remya-debug-launch-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final executable = File('${directory.path}/settings with spaces')
        ..writeAsStringSync('#!/bin/sh\nprintf started > "\$0.started"\n');
      expect(
        (await Process.run('chmod', ['+x', '--', executable.path])).exitCode,
        0,
      );
      await openRemyaSettings(debugExecutable: executable);
      final marker = File('${executable.path}.started');
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!marker.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(marker.readAsStringSync(), 'started');
    },
  );

  test('missing debug build reports the build command instead of using release config', () async {
    await expectLater(
      openRemyaSettings(debugExecutable: File('/nonexistent/remya_settings')),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'build guidance',
          contains('fvm flutter build linux --debug'),
        ),
      ),
    );
  });
}
