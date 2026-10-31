import 'package:material_ui/material_ui.dart';

import 'features/date_time/application/date_time_controller.dart';
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
    this.scheduler,
  });
  final AppPreferencesController? preferences;
  final DateTimeController? dateTime;
  final SettingsScheduler? scheduler;
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
                status: SettingsStatus(
                  navigatorKey: _navigatorKey,
                  preferences: _preferences,
                  dateTime: widget.dateTime,
                ),
              );
            },
          ),
        ),
      ),
    );
    return widget.dateTime == null
        ? app
        : DateTimeScope(controller: widget.dateTime!, child: app);
  }
}
