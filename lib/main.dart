import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';

void main() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      "Remy'a Settings",
    ], await rootBundle.loadString('LICENSE'));
  });
  runApp(const RemyaSettingsApp());
}
