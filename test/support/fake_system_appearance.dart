import 'package:remya_settings/features/appearance/data/system_appearance_backend.dart';

class FakeSystemAppearance implements SystemAppearanceBackend {
  FakeSystemAppearance({this.mode = .light});
  SystemThemeMode mode;
  Object? applyError;
  int applyCalls = 0;

  @override
  Future<SystemThemeState> read() async =>
      SystemThemeState(mode: mode, targets: const []);

  @override
  Future<SystemThemeState> apply(SystemThemeMode requested) async {
    applyCalls++;
    if (applyError case final error?) throw error;
    mode = requested;
    return read();
  }
}
