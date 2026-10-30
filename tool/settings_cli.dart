import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:remya_settings_client/settings_contract.dart';

const usage = '''Usage: remya_settings <command> [arguments]
  get <theme|system|catalog|about|page:id|setting-id>  Read state or metadata
  set <setting-id> <value>             Apply an available setting
  list                               List all controls and availability
  search <query>                     Search settings pages
  open [page-id|home|about|licenses|repository]   Open a page or repository
  reload                             Reload configuration and system state
  watch [theme|all]                   Stream changes as JSON lines
  quit                               Stop the settings application/service
  --help                             Show this help

All successful commands print JSON. Writes use the same backend as the GUI.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.singleOrNull == '--help') {
    stdout.write(usage);
    return;
  }
  final client = SettingsClient();
  try {
    final command = arguments.first;
    final args = arguments.skip(1).toList();
    if (command == 'list') {
      if (args.isNotEmpty) throw ArgumentError('list takes no arguments');
      final controls = <dynamic>[];
      String? cursor = '0';
      while (cursor != null) {
        final page = await client.call('List', [cursor]);
        controls.addAll(page['controls'] as List);
        cursor = page['next_cursor'] as String?;
      }
      stdout.writeln(jsonEncode({'api_version': 1, 'controls': controls}));
      return;
    }
    if (command == 'watch') {
      if (args.length > 1 ||
          (args.isNotEmpty && !{'theme', 'all'}.contains(args.single))) {
        throw ArgumentError('watch accepts theme or all');
      }
      await for (final change in client.watch()) {
        if (args.singleOrNull == 'all' || change.topic == 'theme') {
          stdout.writeln(
            jsonEncode({'topic': change.topic, 'value': change.value}),
          );
        }
      }
      return;
    }
    const methods = {
      'get': 'Get',
      'set': 'Set',
      'list': 'List',
      'search': 'Search',
      'open': 'Open',
      'reload': 'Reload',
      'quit': 'Quit',
    };
    final method = methods[command];
    if (method == null) throw ArgumentError('Unknown command: $command');
    final values = command == 'open' && args.isEmpty ? ['home'] : args;
    stdout.writeln(jsonEncode(await client.call(method, values)));
  } catch (error) {
    stderr.writeln(
      jsonEncode({
        'error': {
          'code': error is DBusMethodResponseException
              ? error.errorName
              : error is ArgumentError
              ? 'InvalidArgument'
              : 'ConnectionFailed',
          'message': error.toString(),
        },
      }),
    );
    exitCode = error is ArgumentError ? 2 : 1;
  } finally {
    await client.close();
  }
}
