import 'package:material_ui/material_ui.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../application/applications_controller.dart';
import 'application_icon.dart';

String _size(int? bytes) {
  if (bytes == null) return 'Size unavailable';
  return bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KiB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

class InstalledAppsPage extends StatefulWidget {
  const InstalledAppsPage({
    super.key,
    required this.controller,
    required this.formatDate,
  });
  final ApplicationsController controller;
  final Future<String> Function(String) formatDate;
  @override
  State<InstalledAppsPage> createState() => _InstalledAppsPageState();
}

class _InstalledAppsPageState extends State<InstalledAppsPage> {
  String _query = '';
  String _sort = 'Name';
  String _source = 'All sources';
  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  Future<void> _details(InstalledApplication app) => showDialog<void>(
    context: context,
    builder: (_) => _AppDetails(
      app: app,
      controller: widget.controller,
      formatDate: widget.formatDate,
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final apps = controller.applications
          .where(
            (a) =>
                '${a.name} ${a.raw['package'] ?? ''}'.toLowerCase().contains(
                  _query.toLowerCase(),
                ) &&
                (_source == 'All sources' || a.source == _source),
          )
          .toList();
      apps.sort((a, b) {
        int result = 0;
        if (_sort == 'Size') {
          result = a.size == null
              ? (b.size == null ? 0 : 1)
              : (b.size == null ? -1 : b.size!.compareTo(a.size!));
        }
        if (_sort == 'Installation date') {
          result = a.installed == null
              ? (b.installed == null ? 0 : 1)
              : (b.installed == null
                    ? -1
                    : b.installed!.compareTo(a.installed!));
        }
        return result != 0
            ? result
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                const Text(
                  'Applications registered with this desktop. Package sizes may be shared by several launchers; Flatpak runtimes and application data are not included.',
                ),
                const SizedBox(height: 16),
                SettingsSurface(
                  padding: .zero,
                  child: Column(
                    children: [
                      SettingRow(
                        id: 'installed.15735a25',
                        label: const Text('Search installed apps'),
                        control: SizedBox(
                          width: 232,
                          child: TextField(
                            key: const ValueKey('installed-search'),
                            decoration: const InputDecoration(
                              labelText: 'Application or package',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                            onChanged: (v) => setState(() => _query = v),
                          ),
                        ),
                      ),
                      SettingRow(
                        id: 'installed.3bf3689a',
                        label: const Text('Sort by'),
                        control: DropdownMenu<String>(
                          initialSelection: _sort,
                          dropdownMenuEntries: [
                            for (final name in [
                              'Name',
                              'Size',
                              'Installation date',
                            ])
                              DropdownMenuEntry(value: name, label: name),
                          ],
                          onSelected: (v) {
                            if (v != null) setState(() => _sort = v);
                          },
                        ),
                      ),
                      SettingRow(
                        id: 'installed.765cf6c3',
                        label: const Text('Filter source'),
                        control: DropdownMenu<String>(
                          initialSelection: _source,
                          dropdownMenuEntries: [
                            for (final name in [
                              'All sources',
                              ...controller.applications
                                  .map((a) => a.source)
                                  .toSet()
                                  .toList()
                                ..sort(),
                            ])
                              DropdownMenuEntry(value: name, label: name),
                          ],
                          onSelected: (v) {
                            if (v != null) setState(() => _source = v);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                if (controller.isBusy) const LinearProgressIndicator(),
                if (controller.errorMessage case final error?)
                  SettingsSurface(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        const Icon(Icons.error_outline_rounded),
                        Text(error),
                        TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : controller.reload,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                for (final warning in controller.warnings)
                  Padding(padding: const .only(top: 12), child: Text(warning)),
                Padding(
                  padding: const .symmetric(vertical: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          controller.loaded
                              ? '${apps.length} ${apps.length == 1 ? 'application' : 'applications'}'
                              : 'Reading installed applications…',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh applications',
                        onPressed: controller.isBusy ? null : controller.reload,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
                if (apps.isEmpty && controller.loaded)
                  const SettingsSurface(child: Text('No applications found')),
              ],
            ),
          ),
          SliverList.builder(
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return Padding(
                padding: const .only(bottom: 8),
                child: SettingsSurface(
                  padding: .zero,
                  child: InkWell(
                    key: ValueKey('installed-${app.id}'),
                    onTap: controller.isBusy ? null : () => _details(app),
                    child: Padding(
                      padding: const .all(20),
                      child: Row(
                        children: [
                          ApplicationIcon(icon: app.icon, size: 48),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: .start,
                              children: [
                                Text(
                                  app.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                DefaultTextStyle(
                                  style: Theme.of(context).textTheme.bodySmall!,
                                  child: Wrap(
                                    spacing: 16,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        app.source == 'pacman'
                                            ? 'System package'
                                            : app.source == 'manual'
                                            ? 'Manual installation'
                                            : app.source,
                                      ),
                                      if (app.version case final version?)
                                        Text('Version: $version'),
                                      if (app.size != null)
                                        Text('Size: ${_size(app.size)}'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      );
    },
  );
}

class _AppDetails extends StatefulWidget {
  const _AppDetails({
    required this.app,
    required this.controller,
    required this.formatDate,
  });
  final InstalledApplication app;
  final ApplicationsController controller;
  final Future<String> Function(String) formatDate;
  @override
  State<_AppDetails> createState() => _AppDetailsState();
}

class _AppDetailsState extends State<_AppDetails> {
  late final Future<String>? _date = widget.app.installed == null
      ? null
      : widget.formatDate(
          DateTime.fromMillisecondsSinceEpoch(
            widget.app.installed! * 1000,
            isUtc: true,
          ).toLocal().toIso8601String().substring(0, 10),
        );
  Future<void> _remove() async {
    final app = widget.app;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Uninstall ${app.name}?'),
        content: Text(
          '${app.reason}\n\n${app.raw['package'] ?? app.id}\n${(app.raw['related'] as List).join('\n')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context);
    await widget.controller.uninstall(app);
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return AlertDialog(
      title: Row(
        children: [
          ApplicationIcon(icon: app.icon, size: 48),
          const SizedBox(width: 16),
          Expanded(child: Text(app.name)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            children: [
              Text('Version: ${app.version ?? 'Unavailable'}'),
              Text('Source: ${app.source}'),
              Text('Package: ${app.raw['package'] ?? 'Not managed'}'),
              Text('Installed size: ${_size(app.size)}'),
              FutureBuilder<String>(
                future: _date,
                builder: (context, snapshot) => Text(
                  'Installed on: ${snapshot.data ?? (snapshot.hasError
                          ? 'Unavailable'
                          : _date == null
                          ? 'Unavailable'
                          : 'Reading…')}',
                ),
              ),
              const SizedBox(height: 12),
              Text('Location: ${app.raw['location'] ?? 'Unavailable'}'),
              const SizedBox(height: 16),
              Text(app.reason),
              const SizedBox(height: 16),
              const ExpansionTile(
                title: Text('Advanced'),
                children: [
                  ListTile(
                    leading: Icon(Icons.construction_rounded),
                    title: Text('Permissions, repair and reset'),
                    subtitle: Text(
                      'Not implemented. Application data is retained.',
                    ),
                    enabled: false,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          style: destructiveFilledButtonStyle(context),
          onPressed: app.canUninstall && !widget.controller.isBusy
              ? _remove
              : null,
          child: const Text('Uninstall'),
        ),
      ],
    );
  }
}
