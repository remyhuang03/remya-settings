import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../../settings/domain/settings_catalog.dart';

const appVersion = '0.1.0+2026-10-26';
const repositoryUrl = 'https://github.com/remyhuang03/remya-settings';

Future<void> openSettingsRepository() async {
  final result = await Process.run('xdg-open', [repositoryUrl]);
  if (result.exitCode != 0) {
    throw const ProcessException('xdg-open', [
      repositoryUrl,
    ], 'Unable to open the repository.');
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.catalog, required this.onLicenses});
  final SettingsCatalog catalog;
  final VoidCallback onLicenses;

  Future<void> _openRepository(BuildContext context) async {
    try {
      await openSettingsRepository();
      return;
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
    final controls = catalog.pages.expand((page) => page.controls);
    final supported = controls
        .where((item) => item.availability == .available)
        .length;
    final pending = controls
        .where((item) => item.availability == .planned)
        .length;
    final unsupported = controls.length - supported - pending;
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
              Text(
                'v$appVersion',
                style: text.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSurface(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text('Settings coverage', style: text.titleMedium),
              const SizedBox(height: 16),
              Wrap(
                spacing: 40,
                runSpacing: 16,
                children: [
                  for (final stat in [
                    ('Supported', supported),
                    ('Not yet done', pending),
                    ('Total', controls.length),
                  ])
                    Column(
                      crossAxisAlignment: .start,
                      mainAxisSize: .min,
                      children: [
                        Text(
                          '${stat.$2}',
                          key: ValueKey('coverage-${stat.$1}'),
                          style: text.headlineSmall,
                        ),
                        Text(stat.$1, style: text.bodyMedium),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('$unsupported unsupported', style: text.bodySmall),
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
                onTap: onLicenses,
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
