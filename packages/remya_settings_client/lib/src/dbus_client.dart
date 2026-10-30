import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';

const settingsBusName = 'top.remya.settings.Service1';
const settingsInterface = 'top.remya.settings.Settings1';
const settingsObjectPath = '/top/remya/settings';

/// Method arity is shared by CLI validation, clients, and server introspection.
const settingsMethods = {
  'Get': 1,
  'Set': 2,
  'List': 1,
  'Search': 1,
  'Open': 1,
  'Reload': 0,
  'Quit': 0,
};

typedef SettingsChange = ({String topic, Map<String, dynamic> value});

class SettingsClient {
  SettingsClient({DBusClient? bus}) : _bus = bus ?? DBusClient.session();
  final DBusClient _bus;
  late final _object = DBusRemoteObject(
    _bus,
    name: settingsBusName,
    path: DBusObjectPath(settingsObjectPath),
  );

  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    if (settingsMethods[method] != arguments.length) {
      throw ArgumentError('Unknown method or invalid arguments: $method');
    }
    final reply = await _object
        .callMethod(
          settingsInterface,
          method,
          arguments.map(DBusString.new),
          replySignature: DBusSignature('s'),
        )
        .timeout(const Duration(seconds: 30));
    return jsonDecode(reply.returnValues.single.asString())
        as Map<String, dynamic>;
  }

  Stream<SettingsChange> get changes =>
      DBusRemoteObjectSignalStream(
        object: _object,
        interface: settingsInterface,
        name: 'Changed',
        signature: DBusSignature('ss'),
      ).map(
        (signal) => (
          topic: signal.values[0].asString(),
          value:
              jsonDecode(signal.values[1].asString()) as Map<String, dynamic>,
        ),
      );

  Stream<SettingsChange> watch() async* {
    final pending = StreamController<SettingsChange>();
    final subscription = changes.listen(pending.add, onError: pending.addError);
    try {
      yield (topic: 'theme', value: await call('Get', ['theme']));
      await for (final change in pending.stream) {
        // Treat buffered theme signals as invalidations to avoid stale snapshots.
        yield change.topic == 'theme'
            ? (topic: 'theme', value: await call('Get', ['theme']))
            : change;
      }
    } finally {
      await subscription.cancel();
      unawaited(pending.close());
    }
  }

  Future<void> close() => _bus.close();
}
