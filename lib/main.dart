import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'features/appearance/application/app_preferences_controller.dart';
import 'features/appearance/data/app_preferences_file.dart';
import 'features/appearance/data/system_appearance_backend.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      "Remy'a Settings",
    ], await rootBundle.loadString('LICENSE'));
    yield LicenseEntryWithLineBreaks([
      'Rust backend dependencies',
    ], await rootBundle.loadString('assets/licenses/rust-dependencies.txt'));
  });
  await RustSystemAppearanceBackend.initialize();
  final preferences = AppPreferencesController(
    store: AppPreferencesFile(AppPreferencesFile.resolve()),
    systemAppearance: const RustSystemAppearanceBackend(),
  );
  await preferences.reload();
  runApp(RemyaSettingsApp(preferences: preferences));
}
