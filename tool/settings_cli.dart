import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:remya_settings_client/settings_contract.dart';

const usage = '''Usage: remya_settings <command> [arguments]
  get <theme|system|system-information|hostname|display|display-brightness|background|accent|fonts|startup|startup-candidates:query|network|bluetooth|sound|power|battery-saver|battery-history:json|cameras|account-information|updates|font-search:query|font:family|catalog|about|page:id|setting-id>  Read state or metadata
  get remya-bar.clock-seconds        Read the bar clock preference
  get remya-bar.folded-apps           List folded app tray IDs
  get remya-bar.layout                Read bar pill groups and options
  get notifications                   Read notification and Do Not Disturb preferences
  set <setting-id> <value|->           Apply an available setting; - reads the value from stdin
  install-appimage <path>            Install an AppImage and show its progress in Settings
  list                               List all controls and availability
  search <query>                     Search settings pages
  open [page-id|home|about|licenses|repository]   Open a page or repository
  resolve <appearance|date-time|display|hostname|background|default-apps|startup|network|power|cameras:node-name> <system|settings>  Resolve a configuration conflict
  resolve display <keep|revert>      Confirm or undo a pending display change
  reload                             Reload configuration and system state
  watch [theme|all]                   Stream changes as JSON lines
  restart                            Restart the system (save work first)
  close                              Close the GUI and keep Settings resident
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
    if (command == 'install-appimage') {
      if (args.length != 1) {
        throw ArgumentError('install-appimage takes one path');
      }
      // Relative paths come from a shell; the service only accepts absolute ones.
      final path = File(args.single).absolute.path;
      stdout.writeln(
        jsonEncode(await client.call('Set', ['appimages.install', path])),
      );
      await client.call('Open', ['appimages']);
      return;
    }
    const methods = {
      'get': 'Get',
      'set': 'Set',
      'list': 'List',
      'search': 'Search',
      'open': 'Open',
      'reload': 'Reload',
      'resolve': 'Resolve',
      'quit': 'Quit',
      'close': 'Close',
      'restart': 'Restart',
    };
    final method = methods[command];
    if (method == null) throw ArgumentError('Unknown command: $command');
    // Passwords stay out of the process list by arriving on stdin.
    final values = command == 'open' && args.isEmpty
        ? ['home']
        : command == 'set' && args.length == 2 && args[1] == '-'
        ? [args[0], (await utf8.decoder.bind(stdin).join()).trim()]
        : args;
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
