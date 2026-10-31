import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remya_settings_client/settings_contract.dart';

void main() {
  test('native D-Bus schema retains the client method arities and signal', () {
    final xml = File('packages/remya_settings_client/api/settings1.xml')
        .readAsStringSync();
    final methods = {
      for (final match in RegExp(
        r'<method name="(\w+)">([\s\S]*?)</method>',
      ).allMatches(xml))
        match[1]!: RegExp('direction="in"').allMatches(match[2]!).length,
    };
    expect(methods, settingsMethods);
    expect(xml, contains('interface name="$settingsInterface"'));
    expect(
      xml,
      contains(
        '<signal name="Changed"><arg type="s"/><arg type="s"/></signal>',
      ),
    );
  });
}
