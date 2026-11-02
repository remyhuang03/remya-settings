import 'features/applications/application/applications_controller.dart';
import 'features/default_apps/application/default_apps_controller.dart';
import 'features/network/application/network_controller.dart';
import 'features/system_information/application/hostname_controller.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'features/background/application/background_controller.dart';
import 'features/display/application/display_controller.dart';
import 'features/fonts/application/fonts_controller.dart';
import 'features/integration/settings_scheduler.dart';
import 'features/night_light/application/night_light_controller.dart';
import 'app.dart';
import 'features/integration/service_controllers.dart';

import 'package:remya_settings_client/remya_settings_client.dart';

import 'features/appearance/data/app_preferences_file.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  if (kDebugMode) {
    final root = await const MethodChannel('top.remya.paths')
        .invokeMethod<String>('repositoryDirectory');
    if (root != null) AppPreferencesFile.debugRepository = Directory(root);
  }
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      "Remy'a Settings",
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Rust backend dependencies',
    ], await rootBundle.loadString('assets/licenses/rust-dependencies.txt'));
  });
  final client = SettingsClient();
  final preferences = ServicePreferencesController(client);
  final dateTime = ServiceDateTimeController(client);
  final display = DisplayController(ServiceDisplayBackend(client));
  final nightLight = NightLightController(
    read: () => client.call('Get', ['night-light']),
    write: (id, value) => client.call('Set', [id, value]),
    resolve: (source) => client.call('Resolve', ['night-light', source]),
  );
  final hostname = HostnameController(
    read: client.readHostname,
    renameName: client.renameHostname,
    resolve: client.resolveHostname,
  );
  final background = BackgroundController(
    read: () => client.call('Get', ['background']),
    write: (id, value) => client.call('Set', [id, value]),
    resolve: (source) => client.call('Resolve', ['background', source]),
  );
  final fonts = FontsController(
    read: () => client.call('Get', ['fonts']),
    write: (id, value) => client.call('Set', [id, value]),
  );
  final defaultApps = DefaultAppsController(
    read: client.readDefaultApps,
    applications: client.searchDefaultApplications,
    searchTypes: client.searchDefaultTypes,
    write: (id, app, types) =>
        client.setDefaultApplication(id, app, types: types),
    resolve: client.resolveDefaultApps,
  );
  final appImages = AppImagesController(
    read: client.readAppImages,
    write: (id, value) => client.call('Set', [id, value]),
    setSource: client.setAppImageSource,
    formatDate: client.formatCalendarDate,
  );
  final applications = ApplicationsController(
    read: client.readInstalledApplications,
    remove: client.uninstallApplication,
    formatDate: client.formatCalendarDate,
    readExternalTools: client.readExternalTools,
    openExternalTool: client.openExternalTool,
    appImages: appImages,
  );
  final network = NetworkController(
    read: client.readNetwork,
    write: (id, value) => client.call('Set', [id, value]),
    resolve: client.resolveNetwork,
    formatDate: client.formatCalendarDate,
    readTraffic: client.readNetworkTraffic,
  );
  final navigation = ValueNotifier<String?>(null);
  final scheduler = SettingsScheduler([
    preferences.reload,
    dateTime.reload,
    display.reload,
    nightLight.reload,
    hostname.reload,
    background.reload,
    network.reload,
  ]);
  runApp(
    RemyaSettingsApp(
      preferences: preferences,
      dateTime: dateTime,
      display: display,
      nightLight: nightLight,
      hostname: hostname,
      background: background,
      fonts: fonts,
      defaultApps: defaultApps,
      applications: applications,
      network: network,
      navigation: navigation,
      scheduler: scheduler,
      systemInformation: client.readSystemInformation,
    ),
  );
  client.changes.listen((change) {
    switch (change.topic) {
      case 'navigation':
        navigation.value = change.value['page'] as String;
        const MethodChannel('top.remya.paths').invokeMethod<void>('show');
      case 'error':
        final message = change.value['message'];
        if (message is String) {
          preferences.reportError(message);
        } else {
          preferences.reload();
        }
      case 'theme' || 'accent':
        preferences.reload();
      case 'background':
        background.apply(change.value);
      case 'installed-apps':
        applications.reload();
        defaultApps.reload();
      case 'appimages':
        appImages.apply(change.value);
        applications.reload();
        defaultApps.reload();
      case 'default-apps':
        defaultApps.reload();
      case 'fonts':
        fonts.reload();
      case 'network':
        network.apply(change.value);
      case 'date-time':
        dateTime.reload();
      case 'hostname':
        hostname.reload();
      case 'display':
        display.reload();
      case 'night-light':
        nightLight.apply(change.value);
    }
  }); // The native runner forwards the initial page separately from VM arguments.
  final page = await const MethodChannel('top.remya.paths')
      .invokeMethod<String>('initialPage');
  navigation.value = page ?? 'home';
  await Future.wait([scheduler.refresh(), defaultApps.reload()]);
}
