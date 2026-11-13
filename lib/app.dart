import 'features/integration/service_controllers.dart';
import 'features/appearance/domain/app_preferences.dart';
import 'features/storage/application/storage_controller.dart';
import 'features/camera/application/camera_controller.dart';
import 'features/updates/application/updates_controller.dart';
import 'features/sound/application/sound_controller.dart';
import 'features/account/application/account_controller.dart';
import 'features/bluetooth/application/bluetooth_controller.dart';
import 'features/applications/application/applications_controller.dart';
import 'features/default_apps/application/default_apps_controller.dart';
import 'features/startup/application/startup_controller.dart';
import 'features/network/application/network_controller.dart';
import 'features/system_information/application/hostname_controller.dart';

import 'package:remya_client/settings_contract.dart';
import 'package:material_ui/material_ui.dart';

import 'features/background/application/background_controller.dart';
import 'features/fonts/application/fonts_controller.dart';
import 'features/date_time/application/date_time_controller.dart';
import 'features/display/application/display_controller.dart';
import 'features/night_light/application/night_light_controller.dart';
import 'features/integration/settings_status.dart';
import 'features/integration/settings_scheduler.dart';
import 'features/appearance/application/app_preferences_controller.dart';
import 'features/settings/domain/settings_catalog.dart';
import 'features/settings/presentation/settings_shell.dart';
import 'features/settings/presentation/settings_title_bar.dart';

class RemyaSettingsApp extends StatefulWidget {
  const RemyaSettingsApp({
    super.key,
    this.preferences,
    this.client,
    this.account,
    this.navigation,
    this.dateTime,
    this.display,
    this.nightLight,
    this.scheduler,
    this.systemInformation,
    this.hostname,
    this.background,
    this.fonts,
    this.defaultApps,
    this.startup,
    this.storage,
    this.applications,
    this.network,
    this.bluetooth,
    this.sound,
    this.cameras,
    this.updates,
  });
  final AccountController? account;
  final BackgroundController? background;
  final FontsController? fonts;
  final DefaultAppsController? defaultApps;
  final StartupController? startup;
  final StorageController? storage;
  final ApplicationsController? applications;
  final NetworkController? network;
  final BluetoothController? bluetooth;
  final SoundController? sound;
  final CameraController? cameras;
  final UpdatesController? updates;
  final AppPreferencesController? preferences;
  final SettingsClient? client;
  final DateTimeController? dateTime;
  final DisplayController? display;
  final NightLightController? nightLight;
  final SettingsScheduler? scheduler;
  final SystemInformationReader? systemInformation;
  final HostnameController? hostname;
  final ValueNotifier<String?>? navigation;

  @override
  State<RemyaSettingsApp> createState() => _RemyaSettingsAppState();
}

class _RemyaSettingsAppState extends State<RemyaSettingsApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final _client = widget.client ?? SettingsClient();
  late var _catalog = SettingsCatalog.load(client: _client);
  late final _preferences =
      widget.preferences ?? ServicePreferencesController(_client);

  @override
  void dispose() {
    _catalog.then((catalog) => catalog.dispose(), onError: (Object _) {});
    if (widget.client == null) _client.close();
    widget.scheduler?.dispose();
    _preferences.dispose();
    widget.account?.dispose();
    widget.dateTime?.dispose();
    widget.display?.dispose();
    widget.nightLight?.dispose();
    widget.hostname?.dispose();
    widget.background?.dispose();
    widget.fonts?.dispose();
    widget.defaultApps?.dispose();
    widget.startup?.dispose();
    widget.storage?.dispose();
    widget.applications?.dispose();
    widget.network?.dispose();
    widget.bluetooth?.dispose();
    widget.sound?.dispose();
    widget.cameras?.dispose();
    widget.updates?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppPreferencesScope(
      controller: _preferences,
      child: ListenableBuilder(
        listenable: _preferences,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          title: "Remy'a Settings",
          debugShowCheckedModeBanner: false,
          theme: _preferences.preferences.theme(.light),
          darkTheme: _preferences.preferences.theme(.dark),
          themeMode: _preferences.preferences.themeMode.materialMode,
          builder: (context, child) => Overlay.wrap(
            child: Column(
              children: [
                const SettingsTitleBar(),
                Expanded(child: child!),
              ],
            ),
          ),
          home: FutureBuilder<SettingsCatalog>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _CoreUnavailable(
                  error: snapshot.error!,
                  onRetry: () => setState(
                    () => _catalog = SettingsCatalog.load(client: _client),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }
              return SettingsShell(
                catalog: snapshot.data!,
                client: widget.client,
                cameras: widget.cameras,
                account: widget.account,
                sound: widget.sound,
                updates: widget.updates,
                navigation: widget.navigation,
                scheduler: widget.scheduler,
                systemInformation: widget.systemInformation,
                topStatus: widget.hostname == null
                    ? null
                    : HostnameStatus(
                        controller: widget.hostname!,
                        navigatorKey: _navigatorKey,
                      ),
                status: SettingsStatus(
                  navigatorKey: _navigatorKey,
                  preferences: _preferences,
                  dateTime: widget.dateTime,
                  display: widget.display,
                  nightLight: widget.nightLight,
                  background: widget.background,
                  defaultApps: widget.defaultApps,
                  network: widget.network,
                  sound: widget.sound,
                ),
              );
            },
          ),
        ),
      ),
    );
    final withHostname = widget.hostname == null
        ? app
        : HostnameScope(controller: widget.hostname!, child: app);
    final withDisplay = widget.display == null
        ? withHostname
        : DisplayScope(controller: widget.display!, child: withHostname);
    final withNightLight = widget.nightLight == null
        ? withDisplay
        : NightLightScope(controller: widget.nightLight!, child: withDisplay);
    final withBackground = widget.background == null
        ? withNightLight
        : BackgroundScope(
            controller: widget.background!,
            child: withNightLight,
          );
    final withFonts = widget.fonts == null
        ? withBackground
        : FontsScope(controller: widget.fonts!, child: withBackground);
    final withDefaultApps = widget.defaultApps == null
        ? withFonts
        : DefaultAppsScope(controller: widget.defaultApps!, child: withFonts);
    final withStartup = widget.startup == null
        ? withDefaultApps
        : StartupScope(controller: widget.startup!, child: withDefaultApps);
    final withApplications = widget.applications == null
        ? withStartup
        : ApplicationsScope(
            controller: widget.applications!,
            child: withStartup,
          );
    final withStorage = widget.storage == null
        ? withApplications
        : StorageScope(controller: widget.storage!, child: withApplications);
    final withNetwork = widget.network == null
        ? withStorage
        : NetworkScope(controller: widget.network!, child: withStorage);
    final withBluetooth = widget.bluetooth == null
        ? withNetwork
        : BluetoothScope(controller: widget.bluetooth!, child: withNetwork);
    return widget.dateTime == null
        ? withBluetooth
        : DateTimeScope(controller: widget.dateTime!, child: withBluetooth);
  }
}

class _CoreUnavailable extends StatelessWidget {
  const _CoreUnavailable({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const .all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: .min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Remya Core is not available',
                  style: text.headlineSmall,
                  textAlign: .center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Settings is a window for Remya Core, a separate background '
                  'service (remyad) that reads and applies your settings. '
                  'Install or start Remya Core, then retry.',
                  textAlign: .center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  '$error',
                  style: text.bodySmall,
                  textAlign: .center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  autofocus: true,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
