import 'features/camera/application/camera_controller.dart';
import 'features/updates/application/updates_controller.dart';
import 'features/sound/application/sound_controller.dart';
import 'features/account/application/account_controller.dart';
import 'features/bluetooth/application/bluetooth_controller.dart';
import 'features/applications/application/applications_controller.dart';
import 'features/default_apps/application/default_apps_controller.dart';
import 'features/network/application/network_controller.dart';
import 'features/system_information/application/hostname_controller.dart';

import 'package:remya_settings_client/settings_contract.dart';
import 'package:material_ui/material_ui.dart';

import 'features/background/application/background_controller.dart';
import 'features/fonts/application/fonts_controller.dart';
import 'features/date_time/application/date_time_controller.dart';
import 'features/display/application/display_controller.dart';
import 'features/night_light/application/night_light_controller.dart';
import 'features/integration/settings_status.dart';
import 'features/integration/settings_scheduler.dart';
import 'features/appearance/application/app_preferences_controller.dart';
import 'features/appearance/data/app_preferences_file.dart';
import 'features/appearance/data/system_appearance_backend.dart';
import 'features/appearance/domain/app_preferences.dart';
import 'features/settings/domain/settings_catalog.dart';
import 'features/settings/presentation/settings_shell.dart';
import 'features/settings/presentation/settings_title_bar.dart';

class RemyaSettingsApp extends StatefulWidget {
  const RemyaSettingsApp({
    super.key,
    this.preferences,
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
  final ApplicationsController? applications;
  final NetworkController? network;
  final BluetoothController? bluetooth;
  final SoundController? sound;
  final CameraController? cameras;
  final UpdatesController? updates;
  final AppPreferencesController? preferences;
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
  late final _catalog = SettingsCatalog.load();
  late final _preferences =
      widget.preferences ??
      AppPreferencesController(
        store: AppPreferencesFile(AppPreferencesFile.resolve()),
        systemAppearance: const RustSystemAppearanceBackend(),
      );

  @override
  void dispose() {
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
                return const Scaffold(
                  body: Center(
                    child: Padding(
                      padding: .all(32),
                      child: Text(
                        'Unable to load settings. Check the application assets and restart.',
                      ),
                    ),
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
    final withApplications = widget.applications == null
        ? withDefaultApps
        : ApplicationsScope(
            controller: widget.applications!,
            child: withDefaultApps,
          );
    final withNetwork = widget.network == null
        ? withApplications
        : NetworkScope(controller: widget.network!, child: withApplications);
    final withBluetooth = widget.bluetooth == null
        ? withNetwork
        : BluetoothScope(controller: widget.bluetooth!, child: withNetwork);
    return widget.dateTime == null
        ? withBluetooth
        : DateTimeScope(controller: widget.dateTime!, child: withBluetooth);
  }
}
