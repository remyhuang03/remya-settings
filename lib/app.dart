import 'package:material_ui/material_ui.dart';

class RemyaSettingsApp extends StatelessWidget {
  const RemyaSettingsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Remy'a Settings",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          dynamicSchemeVariant: .expressive,
        ),
      ),
      home: Scaffold(appBar: AppBar(title: const Text("Remy'a Settings"))),
    );
  }
}
