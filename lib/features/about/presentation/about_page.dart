import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../settings/presentation/settings_widgets.dart';

const appVersion = '0.1.0+2026-10-26';
const repositoryUrl = 'https://github.com/remyhuang03/remya_settings';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _openRepository(BuildContext context) async {
    try {
      final result = await Process.run('xdg-open', [repositoryUrl]);
      if (result.exitCode == 0) return;
    } on ProcessException {
      // The desktop opener may be missing or unavailable.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the repository.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .all(20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Image.asset(
                'assets/icons/settings.png',
                width: 104,
                height: 104,
                semanticLabel: "Remy'a Settings application icon",
              ),
              const SizedBox(height: 20),
              Text(
                "Remy'a Settings",
                style: text.headlineMedium,
                textAlign: .center,
              ),
              const SizedBox(height: 8),
              const Chip(label: Text('v$appVersion')),
              const SizedBox(height: 16),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Repository'),
                subtitle: const Text(repositoryUrl),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: () => _openRepository(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Third-party licenses'),
                subtitle: const Text(
                  'View licenses for Flutter and dependencies',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: "Remy'a Settings",
                  applicationVersion: appVersion,
                  applicationIcon: Padding(
                    padding: const .all(16),
                    child: Image.asset(
                      'assets/icons/settings.png',
                      width: 64,
                      height: 64,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.policy_outlined),
                title: Text('Project license'),
                subtitle: Text('PolyForm Noncommercial License 1.0.0'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
