import 'dbus_client.dart';

const barClockSecondsSettingId = 'remya-bar.clock-seconds';

extension BarClockClient on SettingsClient {
  Future<bool> readBarClockSeconds() async =>
      (await call('Get', [barClockSecondsSettingId]))['value'] as bool;

  Future<bool> setBarClockSeconds(bool enabled) async =>
      (await call('Set', [barClockSecondsSettingId, '$enabled']))['value']
          as bool;
}
