import 'dart:async';
import 'dart:convert';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../appearance/application/app_preferences_controller.dart';
import '../appearance/data/system_appearance_backend.dart';
import '../appearance/domain/app_preferences.dart';
import '../about/presentation/about_page.dart';
import '../settings/domain/settings_catalog.dart';

class SettingsApi extends DBusObject {
  SettingsApi(this.preferences, this.catalog)
    : super(DBusObjectPath(settingsObjectPath));

  final AppPreferencesController preferences;
  final SettingsCatalog catalog;
  final navigation = ValueNotifier<String?>(null);
  final _bus = DBusClient.session();
  String? _lastTheme;
  String? _lastError;
  Future<void> _pending = Future.value();
  Timer? _watcher;
  bool _reloading = false;
  String? _lastFile;

  Future<void> start() async {
    await _bus.registerObject(this);
    final result = await _bus.requestName(
      settingsBusName,
      flags: {DBusRequestNameFlag.doNotQueue},
    );
    if (result != DBusRequestNameReply.primaryOwner) {
      throw StateError(
        'Another settings service already owns $settingsBusName',
      );
    }
    preferences.addListener(_changed);
    _changed();
    // External edits and atomic replacements share the GUI's validation path.
    _watcher = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_reloading || preferences.isBusy) return;
      _reloading = true;
      try {
        final file = preferences.store.file;
        final content = await file.exists() ? await file.readAsString() : null;
        if (content != _lastFile) {
          _lastFile = content;
          await preferences.reload();
        }
      } catch (error) {
        await emitSignal(settingsInterface, 'Changed', [
          const DBusString('error'),
          DBusString(jsonEncode({'message': '$error'})),
        ]);
      } finally {
        _reloading = false;
      }
    });
  }

  void _changed() {
    if (preferences.isBusy) return;
    if (preferences.errorMessage case final error?) {
      if (error != _lastError) {
        _lastError = error;
        unawaited(
          emitSignal(settingsInterface, 'Changed', [
            const DBusString('error'),
            DBusString(jsonEncode({'message': error})),
          ]),
        );
      }
      return;
    }
    final recovered = _lastError != null;
    _lastError = null;
    final value = jsonEncode(preferences.preferences.toMap());
    if (value == _lastTheme && !recovered) return;
    _lastTheme = value;
    unawaited(
      emitSignal(settingsInterface, 'Changed', [
        const DBusString('theme'),
        DBusString(value),
      ]),
    );
  }

  @override
  List<DBusIntrospectInterface> introspect() => [
    DBusIntrospectInterface(
      settingsInterface,
      methods: [
        for (final entry in settingsMethods.entries)
          DBusIntrospectMethod(
            entry.key,
            args: [
              for (var index = 0; index < entry.value; index++)
                DBusIntrospectArgument(
                  DBusSignature('s'),
                  .in_,
                  name: 'arg$index',
                ),
              DBusIntrospectArgument(DBusSignature('s'), .out, name: 'json'),
            ],
          ),
      ],
      signals: [
        DBusIntrospectSignal(
          'Changed',
          args: [
            DBusIntrospectArgument(DBusSignature('s'), .out, name: 'topic'),
            DBusIntrospectArgument(DBusSignature('s'), .out, name: 'json'),
          ],
        ),
      ],
    ),
  ];

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface != settingsInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    final arity = settingsMethods[methodCall.name];
    if (arity == null) return DBusMethodErrorResponse.unknownMethod();
    if (methodCall.signature != DBusSignature('s' * arity)) {
      return DBusMethodErrorResponse.invalidArgs();
    }
    final result = Completer<DBusMethodResponse>();
    _pending = _pending.then((_) async {
      try {
        final value = await execute(
          methodCall.name,
          methodCall.values.map((value) => value.asString()).toList(),
        );
        result.complete(
          DBusMethodSuccessResponse([DBusString(jsonEncode(value))]),
        );
      } on ArgumentError catch (error) {
        result.complete(
          DBusMethodErrorResponse('$settingsInterface.InvalidArgument', [
            DBusString('$error'),
          ]),
        );
      } on UnsupportedError catch (error) {
        result.complete(
          DBusMethodErrorResponse('$settingsInterface.Unavailable', [
            DBusString('$error'),
          ]),
        );
      } catch (error) {
        result.complete(
          DBusMethodErrorResponse('$settingsInterface.OperationFailed', [
            DBusString('$error'),
          ]),
        );
      }
    });
    return result.future;
  }

  Map<String, dynamic> _system() => {
    'mode': preferences.systemTheme?.mode?.name,
    'targets': [
      for (final target
          in preferences.systemTheme?.targets ?? const <ThemeTargetResult>[])
        {
          'name': target.name,
          'status': target.status.name,
          'detail': target.detail,
        },
    ],
  };

  Future<Map<String, dynamic>> execute(String method, List<String> args) async {
    final controls = catalog.pages.expand((page) => page.controls).toList();
    switch (method) {
      case 'Get':
        final key = args.single;
        if (key == 'about') {
          return {
            'name': "Remy'a Settings",
            'version': appVersion,
            'application_id': 'top.remya.settings',
            'repository': repositoryUrl,
            'license': 'PolyForm-Noncommercial-1.0.0',
            'api_version': 1,
          };
        }
        if (key == 'theme') {
          _checkError();
          return preferences.preferences.toMap();
        }
        if (key == 'system') {
          await preferences.reload();
          _checkError();
          return _system();
        }
        if (key == 'catalog' || key.startsWith('page:')) {
          final raw = jsonDecode(
            await rootBundle.loadString('assets/settings/catalog.json'),
          ) as Map<String, dynamic>;
          final pages = (raw['pages'] as List).cast<Map<String, dynamic>>();
          if (key.startsWith('page:')) {
            return pages.firstWhere(
              (page) => page['id'] == key.substring(5),
              orElse: () => throw ArgumentError('Unknown page: $key'),
            );
          }
          return {
            ...raw,
            'pages': [
              for (final page in pages)
                {
                  'id': page['id'],
                  'title': page['title'],
                  'category': page['category'],
                },
            ],
          };
        }
        final control = controls
            .where((control) => control.id == key)
            .firstOrNull;
        if (control == null) throw ArgumentError('Unknown setting: $key');
        return {
          'id': key,
          'availability': control.availability.name,
          'reason': control.reason,
          'value': key == materialStyleSettingId
              ? preferences.preferences.styleVariant.configKey
              : key == materialThemeModeSettingId
              ? preferences.preferences.themeMode.name
              : null,
        };
      case 'Set':
        final key = args[0];
        final value = args[1];
        final control = controls
            .where((control) => control.id == key)
            .firstOrNull;
        if (control == null) throw ArgumentError('Unknown setting: $key');
        if (control.availability != .available) {
          throw UnsupportedError(control.reason);
        }
        if (key == materialStyleSettingId) {
          if (!ThemeConfig.styles.contains(value)) {
            throw ArgumentError('Invalid style: $value');
          }
          await preferences.setStyleVariant(
            RemyaTheme.fromConfig(ThemeConfig(styleVariant: value))
                .styleVariant,
          );
        } else if (key == materialThemeModeSettingId) {
          if (!{'light', 'dark'}.contains(value)) {
            throw ArgumentError('Invalid mode: $value');
          }
          await preferences.setThemeMode(value == 'dark' ? .dark : .light);
        } else {
          throw UnsupportedError('No operation is implemented for $key');
        }
        _checkError();
        return preferences.preferences.toMap();
      case 'List':
        final offset = int.tryParse(args.single);
        if (offset == null || offset < 0 || offset > controls.length) {
          throw ArgumentError('Invalid list cursor');
        }
        final end = (offset + 32).clamp(0, controls.length);
        return {
          'api_version': 1,
          'next_cursor': end < controls.length ? '$end' : null,
          'controls': [
            for (final control in controls.sublist(offset, end))
              {
                'id': control.id,
                'title': control.title,
                'availability': control.availability.name,
                'reason': control.reason,
              },
          ],
        };
      case 'Search':
        return {
          'pages': [
            for (final page in catalog.search(args.single))
              {'id': page.id, 'title': page.title, 'category': page.category},
          ],
        };
      case 'Open':
        final page = args.single;
        if (page == 'repository') {
          await openSettingsRepository();
          return {'opened': page};
        }
        if (!{'home', 'about', 'licenses'}.contains(page) &&
            !catalog.pages.any((entry) => entry.id == page)) {
          throw ArgumentError('Unknown page: $page');
        }
        navigation.value = page;
        await const MethodChannel('top.remya.paths').invokeMethod<void>('show');
        return {'opened': page};
      case 'Reload':
        await preferences.reload();
        _checkError();
        return {'theme': preferences.preferences.toMap(), 'system': _system()};
      case 'Quit':
        Timer(
          const Duration(milliseconds: 100),
          () =>
              const MethodChannel('top.remya.paths').invokeMethod<void>('quit'),
        );
        return {'quitting': true};
      default:
        throw ArgumentError('Unknown method: $method');
    }
  }

  void _checkError() {
    if (preferences.errorMessage case final error?) throw StateError(error);
  }

  Future<void> close() async {
    _watcher?.cancel();
    preferences.removeListener(_changed);
    navigation.dispose();
    await _bus.close();
  }
}
