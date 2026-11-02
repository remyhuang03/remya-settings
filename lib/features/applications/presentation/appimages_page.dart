import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../application/appimages_controller.dart';
import 'application_icon.dart';

const _appImageTypes = XTypeGroup(
  label: 'AppImage',
  extensions: ['AppImage', 'appimage'],
);

String _mib(num bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

Future<String?> _pickAppImage() async =>
    (await openFile(acceptedTypeGroups: [_appImageTypes]))?.path;

class AppImagesPage extends StatefulWidget {
  const AppImagesPage({
    super.key,
    required this.controller,
    this.pickFile = _pickAppImage,
  });
  final AppImagesController controller;
  final Future<String?> Function() pickFile;
  @override
  State<AppImagesPage> createState() => _AppImagesPageState();
}

class _AppImagesPageState extends State<AppImagesPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  Future<void> _install() async {
    final path = await widget.pickFile();
    if (path != null) {
      await widget.controller.run(appImagesInstallSettingId, path);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final text = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          SettingsSurface(
            padding: .zero,
            child: Column(
              children: [
                SettingRow(
                  id: appImagesInstallSettingId,
                  label: _Label(
                    'Install AppImage',
                    'A copy is kept in ${controller.directory} and added to the app launcher.',
                  ),
                  control: FilledButton.icon(
                    key: const ValueKey('appimages-install'),
                    onPressed: _install,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Choose file'),
                  ),
                ),
                for (final name in controller.installing)
                  _InstallingRow(name: name),
                SettingRow(
                  id: appImagesCheckSettingId,
                  label: _UpdatesLabel(controller: controller),
                  control: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('appimages-check'),
                        onPressed: controller.checking
                            ? null
                            : () => controller.run(
                                appImagesCheckSettingId,
                                'all',
                              ),
                        child: const Text('Check now'),
                      ),
                      if (controller.updatable.isNotEmpty)
                        FilledButton(
                          key: const ValueKey('appimages-update-all'),
                          onPressed: () =>
                              controller.run(appImagesUpdateSettingId, 'all'),
                          child: const Text('Update all'),
                        ),
                    ],
                  ),
                ),
                SettingRow(
                  id: appImagesAutoCheckSettingId,
                  label: const _Label(
                    'Check automatically',
                    'Looks for new releases once a day.',
                  ),
                  control: Switch(
                    value: controller.autoCheck,
                    onChanged: (value) =>
                        controller.run(appImagesAutoCheckSettingId, '$value'),
                  ),
                ),
                if (controller.autoCheck)
                  SettingRow(
                    id: appImagesAutoUpdateSettingId,
                    label: const _Label(
                      'Install updates automatically',
                      'Running applications switch to the new version the next time they open.',
                    ),
                    control: Switch(
                      value: controller.autoUpdate,
                      onChanged: (value) => controller.run(
                        appImagesAutoUpdateSettingId,
                        '$value',
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (controller.errorMessage case final error?) ...[
            const SizedBox(height: 12),
            SettingsSurface(
              child: _StatusLine(
                icon: Icons.error_outline_rounded,
                text: error,
                error: true,
              ),
            ),
          ],
          Padding(
            padding: const .fromLTRB(4, 24, 4, 12),
            child: Text(
              controller.loaded
                  ? '${controller.apps.length} ${controller.apps.length == 1 ? 'application' : 'applications'}'
                  : 'Reading AppImages…',
              style: text.titleMedium,
            ),
          ),
          if (controller.loaded && controller.apps.isEmpty)
            const SettingsSurface(child: Text('No AppImages installed yet.')),
          for (final app in controller.apps)
            Padding(
              padding: const .only(bottom: 8),
              child: _AppCard(app: app, controller: controller),
            ),
        ],
      );
    },
  );
}

class _Label extends StatelessWidget {
  const _Label(this.title, this.subtitle);
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    children: [
      Text(title, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 2),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _UpdatesLabel extends StatefulWidget {
  const _UpdatesLabel({required this.controller});
  final AppImagesController controller;
  @override
  State<_UpdatesLabel> createState() => _UpdatesLabelState();
}

class _UpdatesLabelState extends State<_UpdatesLabel> {
  int? _formatted;
  Future<String>? _date;
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final count = controller.updatable.length;
    final active = controller.apps.where((a) => a.job != null).length;
    if (_formatted != controller.lastCheck) {
      _formatted = controller.lastCheck;
      _date = controller.lastCheck == 0
          ? null
          : controller.formatDate(
              DateTime.fromMillisecondsSinceEpoch(
                controller.lastCheck * 1000,
                isUtc: true,
              ).toLocal().toIso8601String().substring(0, 10),
            );
    }
    return FutureBuilder<String>(
      future: _date,
      builder: (context, snapshot) => _Label(
        active > 0
            ? 'Working on $active ${active == 1 ? 'application' : 'applications'}…'
            : count > 0
            ? '$count ${count == 1 ? 'update' : 'updates'} available'
            : 'Updates',
        _date == null
            ? 'Not checked yet.'
            : 'Last checked: ${snapshot.data ?? '…'}',
      ),
    );
  }
}

class _InstallingRow extends StatelessWidget {
  const _InstallingRow({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const .symmetric(horizontal: 20, vertical: 8),
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        Text('Installing $name…'),
        const SizedBox(height: 8),
        const LinearProgressIndicator(),
      ],
    ),
  );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.text,
    this.error = false,
  });
  final IconData icon;
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final color = error
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: .start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Status always carries an icon and words: color alone would not explain it.
(IconData, String)? _status(AppImageEntry app) {
  if (app.available case final available?) {
    final version = available['version'];
    return (
      Icons.upgrade_rounded,
      version == null ? 'Update available' : 'Update available: $version',
    );
  }
  if (app.source == null) return (Icons.link_off_rounded, 'No update source');
  if (!app.updates) return (Icons.pause_circle_outline_rounded, 'Updates off');
  if (app.checked) return (Icons.check_circle_outline_rounded, 'Up to date');
  return null;
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.app, required this.controller});
  final AppImageEntry app;
  final AppImagesController controller;

  @override
  Widget build(BuildContext context) {
    final status = _status(app);
    return SettingsSurface(
      padding: .zero,
      child: InkWell(
        key: ValueKey('appimage-${app.id}'),
        onTap: () => showDialog<void>(
          context: context,
          builder: (_) => _AppDetails(id: app.id, controller: controller),
        ),
        child: Padding(
          padding: const .all(20),
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              Row(
                children: [
                  ApplicationIcon(icon: app.icon, size: 48),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: [
                        Text(
                          app.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        DefaultTextStyle(
                          style: Theme.of(context).textTheme.bodySmall!,
                          child: Wrap(
                            spacing: 16,
                            runSpacing: 4,
                            children: [
                              if (app.version case final version?)
                                Text('Version: $version'),
                              Text('Size: ${_mib(app.size)}'),
                              if (!app.integrated)
                                const Text('Not in app launcher'),
                            ],
                          ),
                        ),
                        if (app.job == null && status != null) ...[
                          const SizedBox(height: 4),
                          _StatusLine(icon: status.$1, text: status.$2),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (app.available != null && app.job == null)
                    FilledButton.tonal(
                      key: ValueKey('appimage-update-${app.id}'),
                      onPressed: () =>
                          controller.run(appImagesUpdateSettingId, app.id),
                      child: const Text('Update'),
                    )
                  else
                    const Icon(Icons.chevron_right_rounded),
                ],
              ),
              if (app.job case final job?) ...[
                const SizedBox(height: 12),
                _Progress(job: job, app: app, controller: controller),
              ],
              if (app.error case final error? when app.job == null) ...[
                const SizedBox(height: 8),
                _StatusLine(
                  icon: Icons.error_outline_rounded,
                  text: error,
                  error: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.job,
    required this.app,
    required this.controller,
  });
  final Map job;
  final AppImageEntry app;
  final AppImagesController controller;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String;
    final bytes = job['bytes'] as int;
    final total = job['total'] as int;
    final speed = job['speed'] as int;
    final measured =
        (status == 'downloading' || status == 'comparing') && total > 0;
    final label = switch (status) {
      'queued' => 'Waiting…',
      'checking' => 'Checking for updates…',
      'comparing' =>
        'Comparing with the installed version: ${_mib(bytes)} of ${_mib(total)}',
      'downloading' =>
        'Downloading ${_mib(bytes)} of ${_mib(total)}'
            '${speed > 0 ? ' at ${_mib(speed)}/s' : ''}',
      'installing' => 'Installing…',
      _ => status,
    };
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              LinearProgressIndicator(
                key: ValueKey('appimage-progress-${app.id}'),
                value: measured ? (bytes / total).clamp(0.0, 1.0) : null,
              ),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: ValueKey('appimage-cancel-${app.id}'),
          tooltip: 'Cancel',
          onPressed: status == 'installing'
              ? null
              : () => controller.run(appImagesCancelSettingId, app.id),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _AppDetails extends StatefulWidget {
  const _AppDetails({required this.id, required this.controller});
  final String id;
  final AppImagesController controller;
  @override
  State<_AppDetails> createState() => _AppDetailsState();
}

class _AppDetailsState extends State<_AppDetails> {
  late final _source = TextEditingController(text: _custom(_app));
  String? _sourceError;

  AppImageEntry? get _app =>
      widget.controller.apps.where((a) => a.id == widget.id).firstOrNull;
  static String _custom(AppImageEntry? app) =>
      app?.sourceOrigin == 'custom' ? app!.source! : '';

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  Future<void> _saveSource(AppImageEntry app) async {
    final text = _source.text.trim();
    final saved = await widget.controller.saveSource(
      app,
      text.isEmpty ? null : text,
      app.updates,
    );
    if (!mounted) return;
    setState(() {
      _sourceError = saved
          ? null
          : 'Use a GitHub repository URL or an https .zsync URL.';
    });
    // The page banner would repeat the field's own explanation.
    if (!saved) widget.controller.requestError = null;
  }

  Future<void> _trash(AppImageEntry app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move ${app.name} to Trash?'),
        content: const Text(
          'The launcher is removed too. You can restore the file from Trash; application data in your home folder is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Move to Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context);
    await widget.controller.run(appImagesUninstallSettingId, app.id);
  }

  static const _origins = {
    'embedded': 'Published by the application',
    'desktop': 'From the launcher entry',
    'custom': 'Set by you',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final app = _app;
      if (app == null) {
        return AlertDialog(
          title: const Text('AppImage removed'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      }
      final busy = app.job != null;
      return AlertDialog(
        title: Row(
          children: [
            ApplicationIcon(icon: app.icon, size: 48),
            const SizedBox(width: 16),
            Expanded(child: Text(app.name)),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text('Version: ${app.version ?? 'Unavailable'}'),
                Text('Size: ${_mib(app.size)}'),
                Text('Location: ${app.path}'),
                const SizedBox(height: 16),
                Text(
                  'Update source',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  app.source == null
                      ? 'Current: none'
                      : 'Current: ${app.source}\n${_origins[app.sourceOrigin]}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('appimage-source'),
                  controller: _source,
                  decoration: InputDecoration(
                    labelText: 'Custom source',
                    hintText: 'https://github.com/owner/repository',
                    helperText: 'Leave empty to use the source published by the application.',
                    errorText: _sourceError,
                    errorMaxLines: 2,
                    helperMaxLines: 2,
                  ),
                  onSubmitted: (_) => _saveSource(app),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: .centerRight,
                  child: TextButton(
                    key: const ValueKey('appimage-source-save'),
                    onPressed: () => _saveSource(app),
                    child: const Text('Save source'),
                  ),
                ),
                if (app.source != null)
                  SwitchListTile(
                    key: const ValueKey('appimage-updates'),
                    contentPadding: .zero,
                    title: const Text('Include in update checks'),
                    value: app.updates,
                    onChanged: (value) => widget.controller.saveSource(
                      app,
                      app.sourceOrigin == 'custom' ? app.source : null,
                      value,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const ValueKey('appimage-trash'),
            style: destructiveTextButtonStyle(context),
            onPressed: busy ? null : () => _trash(app),
            child: const Text('Move to Trash'),
          ),
          if (!app.integrated)
            TextButton(
              key: const ValueKey('appimage-integrate'),
              onPressed: busy
                  ? null
                  : () => widget.controller.run(
                      appImagesIntegrateSettingId,
                      app.id,
                    ),
              child: const Text('Add to launcher'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const ValueKey('appimage-open'),
            onPressed: () =>
                widget.controller.run(appImagesOpenSettingId, app.id),
            child: const Text('Open'),
          ),
        ],
      );
    },
  );
}
