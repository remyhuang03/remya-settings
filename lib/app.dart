import 'package:material_ui/material_ui.dart';

import 'features/settings/domain/settings_catalog.dart';
import 'features/settings/presentation/settings_shell.dart';
import 'features/settings/presentation/settings_title_bar.dart';

class RemyaSettingsApp extends StatefulWidget {
  const RemyaSettingsApp({super.key});

  @override
  State<RemyaSettingsApp> createState() => _RemyaSettingsAppState();
}

class _RemyaSettingsAppState extends State<RemyaSettingsApp> {
  late final _catalog = SettingsCatalog.load();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Remy'a Settings",
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8054C9),
        dynamicSchemeVariant: .expressive,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F5FA),
      fontFamilyFallback: const [
        'Noto Sans CJK SC',
        'Noto Sans CJK TC',
        'sans-serif',
      ],
    ),
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
        return SettingsShell(catalog: snapshot.data!);
      },
    ),
  );
}
