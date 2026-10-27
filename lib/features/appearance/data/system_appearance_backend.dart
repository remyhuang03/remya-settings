import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../../src/rust/appearance_bridge/api.dart';
import '../../../src/rust/appearance_bridge/frb_generated.dart';

export '../../../src/rust/appearance_bridge/api.dart'
    show
        SystemThemeMode,
        SystemThemeState,
        ThemeTargetResult,
        ThemeTargetStatus;

abstract interface class SystemAppearanceBackend {
  Future<SystemThemeState> read();
  Future<SystemThemeState> apply(SystemThemeMode mode);
}

class RustSystemAppearanceBackend implements SystemAppearanceBackend {
  const RustSystemAppearanceBackend();

  static Future<void> initialize() => AppearanceRustLib.init(
    externalLibrary: ExternalLibrary.open(
      '${File(Platform.resolvedExecutable).parent.path}/lib/libremya_settings_appearance.so',
    ),
  );

  @override
  Future<SystemThemeState> read() => readSystemTheme();

  @override
  Future<SystemThemeState> apply(SystemThemeMode mode) =>
      applySystemTheme(mode: mode);
}
