import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../applications/presentation/application_icon.dart';
import '../application/startup_controller.dart';

class StartupPage extends StatefulWidget {
  const StartupPage({super.key, required this.controller});
  final StartupController controller;
  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  Future<void> _remove(StartupEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${entry.name} from startup?'),
        content: const Text(
          'This removes the startup entry added by you. The application stays installed. System entries can only be turned off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && widget.controller.canChange) {
      await widget.controller.set('startup.remove', {'id': entry.id});
    }
  }

  Future<void> _addApp() async {
    final application = await showDialog<String>(
      context: context,
      builder: (context) => _ApplicationPicker(controller: widget.controller),
    );
    if (application == null || !widget.controller.canChange) return;
    final exists = widget.controller.entries.any((e) => e.id == application);
    await widget.controller.set(
      exists ? 'startup.apps' : 'startup.add-app',
      exists
          ? {'id': application, 'enabled': true}
          : {'application': application},
    );
  }

  Widget _group(List<StartupEntry> entries, String empty) => SettingsSurface(
    padding: .zero,
    child: entries.isEmpty
        ? Padding(
            padding: const .symmetric(horizontal: 20, vertical: 18),
            child: Text(
              empty,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : settingsRows([
            for (final entry in entries)
              _EntryRow(
                key: ValueKey('startup-${entry.id}'),
                entry: entry,
                controller: widget.controller,
                onRemove: () => _remove(entry),
              ),
          ]),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final entries = controller.entries;
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          if (controller.hasConflict) ...[
            _Conflict(controller: controller),
            const SizedBox(height: 12),
          ],
          if (controller.errorMessage case final error?)
            SettingsErrorCard(
              message: error,
              onRetry: controller.isBusy ? null : controller.reload,
            ),
          if (controller.value.containsKey('entries'))
            _Summary(controller: controller)
          else
            const LinearProgressIndicator(),
          if (controller.disabledReason case final reason?
              when !controller.hasConflict && controller.errorMessage == null)
            Padding(
              padding: const .only(top: 12),
              child: _Readout(icon: Icons.info_outline_rounded, text: reason),
            ),
          if ((controller.value['skipped_invalid'] as int? ?? 0) > 0)
            Padding(
              padding: const .only(top: 12),
              child: _Readout(
                icon: Icons.warning_amber_rounded,
                text:
                    '${controller.value['skipped_invalid']} invalid autostart files were skipped.',
              ),
            ),
          SettingsSectionTitle(
            'Added by you',
            trailing: FilledButton.tonalIcon(
              onPressed: controller.canChange ? _addApp : null,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add an app'),
            ),
          ),
          _group(
            entries.where((e) => e.origin != 'system').toList(),
            'Apps you add start here when you sign in.',
          ),
          const SettingsSectionTitle('From the system'),
          _group(
            entries.where((e) => e.origin == 'system').toList(),
            'No system startup apps apply to Hyprland.',
          ),
          AdvancedSection(
            storageKey: const PageStorageKey('startup-advanced'),
            child: SettingRow(
              id: 'startup.add-command',
              label: Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text('Custom command', style: theme.textTheme.bodyLarge),
                  Text(
                    'Run any command when you sign in, such as a sync daemon or script.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              control: FilledButton.tonalIcon(
                onPressed: controller.canChange
                    ? () => showDialog<void>(
                        context: context,
                        builder: (context) =>
                            _CommandDialog(controller: controller),
                      )
                    : null,
                icon: const Icon(Icons.terminal_rounded),
                label: const Text('Add command'),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});
  final StartupController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = controller.entries;
    final enabled = entries.where((e) => e.enabled).length;
    final session = controller.value['session_autostart'];
    final counts = {
      for (final status in ['running', 'finished', 'failed'])
        status: entries.where((e) => e.enabled && e.status == status).length,
    }..removeWhere((_, count) => count == 0);
    return SettingsSurface(
      padding: const .all(24),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          Row(
            spacing: 16,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: .circle,
                ),
                child: Icon(
                  Icons.rocket_launch_outlined,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      '$enabled of ${entries.length} apps start when you sign in',
                      style: theme.textTheme.titleLarge,
                    ),
                    Text(
                      'Turn off apps you do not need right away to sign in faster.',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (controller.value['status_error'] case final String error)
            _Note(icon: Icons.info_outline_rounded, text: error),
          if (session == false)
            const _Note(
              icon: Icons.info_outline_rounded,
              text: 'This session was not started with UWSM, so these apps did not start automatically. Changes apply the next time you sign in with UWSM.',
            )
          else if (counts.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: .center,
              children: [
                Text('Last sign-in', style: theme.textTheme.labelLarge),
                for (final MapEntry(key: status, value: count)
                    in counts.entries)
                  Chip(
                    avatar: Icon(_status(status).$2, size: 18),
                    label: Text('${_status(status).$1}: $count'),
                    visualDensity: .compact,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A quiet explanation inside a card.
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: .circular(16),
      child: Padding(
        padding: const .all(16),
        child: Row(
          crossAxisAlignment: .start,
          spacing: 12,
          children: [
            Icon(icon, size: 20, color: colors.onSurfaceVariant),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    super.key,
    required this.entry,
    required this.controller,
    required this.onRemove,
  });
  final StartupEntry entry;
  final StartupController controller;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final status =
        controller.value['session_autostart'] == true &&
            entry.enabled &&
            entry.status != null
        ? _status(entry.status!)
        : null;
    return Padding(
      padding: const .fromLTRB(20, 10, 8, 10),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          spacing: 12,
          children: [
            // On phone widths the name alone identifies the app.
            if (constraints.maxWidth >= 320) ApplicationIcon(icon: entry.icon),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text(entry.name, style: theme.textTheme.bodyLarge),
                  Text(
                    entry.comment.isEmpty ? entry.exec : entry.comment,
                    style: muted,
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                  if (status != null)
                    Row(
                      spacing: 6,
                      children: [
                        Icon(status.$2, size: 14, color: muted?.color),
                        Text(status.$1, style: muted),
                      ],
                    ),
                ],
              ),
            ),
            Semantics(
              label: 'Start ${entry.name} when you sign in',
              child: Switch(
                key: ValueKey('startup-toggle-${entry.id}'),
                value: entry.enabled,
                onChanged: controller.canChange
                    ? (enabled) => controller.set('startup.apps', {
                        'id': entry.id,
                        'enabled': enabled,
                      })
                    : null,
              ),
            ),
            // A fixed slot keeps every switch in the same column.
            SizedBox(
              width: 40,
              child: entry.removable
                  ? PopupMenuButton<String>(
                      tooltip: 'More options for ${entry.name}',
                      enabled: controller.canChange,
                      onSelected: (_) => onRemove(),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove from startup'),
                        ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Conflict extends StatelessWidget {
  const _Conflict({required this.controller});
  final StartupController controller;
  @override
  Widget build(BuildContext context) => SettingsSurface(
    child: Column(
      crossAxisAlignment: .start,
      spacing: 12,
      children: [
        const _Readout(
          icon: Icons.warning_amber_rounded,
          text: 'Startup apps differ from saved Settings',
        ),
        for (final conflict
            in controller.value['conflicts'] as List? ?? const [])
          Text(
            '${conflict['name']}\nSystem: ${conflict['system'] == true ? 'On' : 'Off'}\nSettings: ${conflict['saved'] == true ? 'On' : 'Off'}',
          ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: controller.canResolve
                  ? controller.useSystemConfiguration
                  : null,
              child: const Text('Use system configuration'),
            ),
            TextButton(
              onPressed: controller.canResolve
                  ? controller.applySavedConfiguration
                  : null,
              child: const Text('Apply Settings configuration'),
            ),
          ],
        ),
      ],
    ),
  );
}

(String, IconData) _status(String status) => switch (status) {
  'running' => ('Running', Icons.play_circle_outline_rounded),
  'finished' => ('Finished', Icons.check_circle_outline_rounded),
  'failed' => ('Failed', Icons.error_outline_rounded),
  _ => ('Not started', Icons.schedule_rounded),
};

class _Readout extends StatelessWidget {
  const _Readout({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    children: [
      Icon(icon, size: 20),
      const SizedBox(width: 8),
      Flexible(child: Text(text)),
    ],
  );
}

class _CommandDialog extends StatefulWidget {
  const _CommandDialog({required this.controller});
  final StartupController controller;
  @override
  State<_CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<_CommandDialog> {
  String _name = '';
  String _command = '';
  String? _error;
  Future<void> _add() async {
    final ok = await widget.controller.set('startup.add-command', {
      'name': _name,
      'command': _command,
    });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _error = widget.controller.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => AlertDialog(
      title: const Text('Add a custom command'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          spacing: 16,
          children: [
            const Text(
              'The command will run the next time you sign in with UWSM.',
            ),
            TextField(
              key: const ValueKey('startup-command-name'),
              autofocus: true,
              enabled: !widget.controller.isBusy,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (value) => setState(() => _name = value),
            ),
            TextField(
              key: const ValueKey('startup-command-exec'),
              enabled: !widget.controller.isBusy,
              decoration: const InputDecoration(
                labelText: 'Command',
                hintText: 'syncthing serve --no-browser',
                helperText:
                    'A program in PATH or an absolute path, with arguments',
              ),
              onChanged: (value) => setState(() => _command = value),
            ),
            if (_error case final error?)
              _Readout(icon: Icons.error_outline_rounded, text: error),
            if (widget.controller.isBusy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.controller.isBusy
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('startup-command-add'),
          onPressed:
              _name.trim().isNotEmpty &&
                  _command.trim().isNotEmpty &&
                  widget.controller.canChange
              ? _add
              : null,
          child: const Text('Add'),
        ),
      ],
    ),
  );
}

class _ApplicationPicker extends StatefulWidget {
  const _ApplicationPicker({required this.controller});
  final StartupController controller;
  @override
  State<_ApplicationPicker> createState() => _ApplicationPickerState();
}

class _ApplicationPickerState extends State<_ApplicationPicker> {
  late Future<Map<String, dynamic>> _candidates = widget.controller.candidates(
    '',
  );
  Timer? _debounce;
  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      setState(() {
        _candidates = widget.controller.candidates(query);
      });
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add an app'),
    content: SizedBox(
      width: 480,
      height: 420,
      child: Column(
        spacing: 12,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Search applications',
              prefixIcon: Icon(Icons.search_rounded),
            ),
            onChanged: _search,
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _candidates,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('${snapshot.error}');
                }
                if (snapshot.connectionState != .done) {
                  return const RemyaLoadingBar();
                }
                final apps =
                    snapshot.data?['applications'] as List? ?? const [];
                if (apps.isEmpty) {
                  return const Center(child: Text('No matching apps'));
                }
                return ListView.builder(
                  itemCount: apps.length,
                  itemBuilder: (context, index) {
                    final app = apps[index] as Map;
                    return ListTile(
                      leading: ApplicationIcon(icon: app['icon'] as String?),
                      title: Text(app['name'] as String),
                      subtitle: Text(app['id'] as String),
                      onTap: () => Navigator.pop(context, app['id'] as String),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
