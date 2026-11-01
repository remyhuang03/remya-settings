import 'features/system_information/application/hostname_controller.dart';

import 'package:remya_settings_client/settings_contract.dart';
import 'package:material_ui/material_ui.dart';

import 'features/background/application/background_controller.dart';
import 'features/fonts/application/fonts_controller.dart';
import 'features/date_time/application/date_time_controller.dart';
import 'features/display/application/display_controller.dart';
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
    this.navigation,
    this.dateTime,
    this.display,
    this.scheduler,
    this.systemInformation,
    this.hostname,
    this.background,
    this.fonts,
  });
  final BackgroundController? background;
  final FontsController? fonts;
  final AppPreferencesController? preferences;
  final DateTimeController? dateTime;
  final DisplayController? display;
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
    widget.dateTime?.dispose();
    widget.display?.dispose();
    widget.hostname?.dispose();
    widget.background?.dispose();
    widget.fonts?.dispose();
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
                  background: widget.background,
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
    final withBackground = widget.background == null
        ? withDisplay
        : BackgroundScope(controller: widget.background!, child: withDisplay);
    final withFonts = widget.fonts == null
        ? withBackground
        : FontsScope(controller: widget.fonts!, child: withBackground);
    return widget.dateTime == null
        ? withFonts
        : DateTimeScope(controller: widget.dateTime!, child: withFonts);
  }
}
