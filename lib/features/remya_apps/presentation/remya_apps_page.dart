import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../../applications/presentation/application_icon.dart';
import '../../settings/domain/settings_catalog.dart';

/// Opens a Remya app's own settings window and reports a failed launch.
Future<void> openRemyaApp(
  BuildContext context,
  SettingsCatalog catalog,
  String app,
  String page,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await catalog.openApp(app, page);
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not open ${catalog.appTitle(app)}: $error'),
      ),
    );
  }
}

/// Installed Remya apps registered with Remya Core, each with its settings pages.
/// The shell reloads registrations on each visit and rebuilds on catalog changes.
class RemyaAppsPage extends StatelessWidget {
  const RemyaAppsPage({super.key, required this.catalog});
  final SettingsCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final apps = catalog.apps;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          'Each Remya app keeps its preferences in its own settings window.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        if (catalog.appsError case final error?)
          SettingsErrorCard(
            message: 'Could not list Remya apps from Remya Core: $error',
            onRetry: catalog.loadingApps ? null : catalog.loadApps,
          ),
        if (apps != null && apps.isEmpty) const _EmptyApps(),
        for (final app in apps ?? const <RemyaApp>[])
          Padding(
            padding: const .only(bottom: 12),
            child: _AppCard(app: app, catalog: catalog),
          ),
      ],
    );
  }
}

class _EmptyApps extends StatelessWidget {
  const _EmptyApps();

  @override
  Widget build(BuildContext context) => SettingsSurface(
    child: Column(
      children: [
        const Icon(Icons.widgets_outlined, size: 40),
        const SizedBox(height: 12),
        Text(
          'No Remya apps are installed',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Apps such as Remya Bar, Remya Launcher and Remya Screen Capture '
          'list their settings here once installed.',
          textAlign: .center,
        ),
      ],
    ),
  );
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.catalog});
  final RemyaApp app;
  final SettingsCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final title = app.title ?? app.id;
    return SettingsSurface(
      key: ValueKey('remya-app-${app.id}'),
      padding: .zero,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .all(20),
            child: Row(
              children: [
                ApplicationIcon(icon: app.icon, size: 48),
                const SizedBox(width: 16),
                Expanded(child: Text(title, style: text.titleMedium)),
                if (app.error == null)
                  FilledButton.tonalIcon(
                    onPressed: () => openRemyaApp(context, catalog, app.id, ''),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open settings'),
                  ),
              ],
            ),
          ),
          if (app.error case final error?)
            Padding(
              padding: const .fromLTRB(20, 0, 20, 20),
              child: Row(
                crossAxisAlignment: .start,
                children: [
                  Icon(Icons.error_outline_rounded, color: colors.error),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Registration file is invalid, so its settings cannot '
                      'open.\n$error',
                    ),
                  ),
                ],
              ),
            ),
          for (final page in app.pages) ...[
            const Divider(height: 1, indent: 20, endIndent: 20),
            Semantics(
              button: true,
              hint: 'Opens in the $title settings window',
              child: InkWell(
                onTap: () => openRemyaApp(context, catalog, app.id, page.id),
                child: Padding(
                  padding: const .symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(child: Text(page.title, style: text.bodyLarge)),
                      const Icon(Icons.open_in_new_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
