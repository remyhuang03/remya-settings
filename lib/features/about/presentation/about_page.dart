import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../../settings/domain/settings_catalog.dart';

const repositoryUrl = 'https://github.com/remyhuang03/remya-settings';

class AboutPage extends StatelessWidget {
  const AboutPage({
    super.key,
    required this.catalog,
    required this.onLicenses,
    this.version,
  });
  final SettingsCatalog catalog;
  final VoidCallback onLicenses;
  final Future<String?>? version;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      FutureBuilder(
        future: version,
        builder: (context, snapshot) => RemyaAboutHeader(
          icon: Image.asset(
            'assets/icons/app_icon.png',
            semanticLabel: "Remy'a Settings application icon",
          ),
          name: "Remy'a Settings",
          version: snapshot.data,
        ),
      ),
      if (catalog.coverage case final coverage?) ...[
        _Coverage(coverage),
        const SizedBox(height: 16),
      ],
      RemyaAboutLinks(repository: repositoryUrl, onLicenses: onLicenses),
    ],
  );
}

class _Coverage extends StatelessWidget {
  const _Coverage(this.coverage);
  final SettingsCoverage coverage;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (:supported, :planned, :total) = coverage;
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text('Settings coverage', style: text.titleMedium),
          const SizedBox(height: 16),
          Wrap(
            spacing: 40,
            runSpacing: 16,
            children: [
              // Every count is shown so the parts visibly add up to the total.
              for (final stat in [
                ('Supported', supported),
                ('Not yet done', planned),
                ('Total', total),
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
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: .circular(4),
            child: LinearProgressIndicator(
              key: const ValueKey('coverage-progress'),
              value: total == 0 ? 0 : supported / total,
              minHeight: 8,
              semanticsLabel: 'Supported share of settings',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${total == 0 ? 0 : (supported * 100 / total).round()}% of settings are supported.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
