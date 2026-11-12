import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';

/// CUPS printers with their state, default choice and queue. Printers are
/// live system state, so the page polls while it is open.
class PrintersPage extends StatefulWidget {
  const PrintersPage({super.key, required this.client, required this.page});
  final SettingsClient client;
  final SettingsPageSpec page;

  @override
  State<PrintersPage> createState() => _PrintersPageState();
}

class _PrintersPageState extends State<PrintersPage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: printersFeature,
  )..reload();
  late final _poll = Timer.periodic(const Duration(seconds: 3), (_) {
    if (!_controller.isBusy) unawaited(_controller.reload());
  });

  /// A rejected action stays visible until the next action.
  String? _failure;

  @override
  void initState() {
    super.initState();
    _poll;
  }

  @override
  void dispose() {
    _poll.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _set(
    String id,
    Map<String, Object> value, {
    String? done,
  }) async {
    final ok = await _controller.set(id, value);
    if (!mounted) return;
    setState(() => _failure = ok ? null : _controller.errorMessage);
    if (ok && done != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    }
  }

  Future<void> _remove(String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text(
          'The printer and its waiting jobs are deleted from CUPS. This cannot '
          'be undone; the printer has to be added again to print to it.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _set(removePrinterId, {'name': name}, done: '$name removed');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final printers = _controller.list('printers');
      return Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(
            widget.page.description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (_failure ?? _controller.errorMessage case final error?)
            SettingsErrorCard(
              message: error,
              onRetry: _controller.isBusy ? null : _controller.reload,
            ),
          if (!_controller.isLoaded)
            const Padding(
              padding: .all(48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (printers.isEmpty)
            const _Empty()
          else
            for (final printer in printers)
              _PrinterCard(
                printer: printer,
                enabled: _controller.canChange,
                onSet: _set,
                onRemove: _remove,
              ),
        ],
      );
    },
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SettingsSurface(
      child: Column(
        spacing: 8,
        children: [
          const Icon(Icons.print_disabled_outlined, size: 48),
          Text('No printers are set up', style: text.titleMedium),
          Text(
            'Printers added to CUPS appear here.',
            style: text.bodyMedium,
            textAlign: .center,
          ),
        ],
      ),
    );
  }
}

/// How a CUPS printer state reads, with an icon so color is not the only cue.
(IconData, String) _status(Map<String, dynamic> printer) =>
    switch (printer['state']) {
      'printing' => (Icons.print_rounded, 'Printing'),
      'stopped' => (Icons.pause_circle_outline_rounded, 'Paused'),
      _ => (Icons.check_circle_outline_rounded, 'Ready'),
    };

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({
    required this.printer,
    required this.enabled,
    required this.onSet,
    required this.onRemove,
  });
  final Map<String, dynamic> printer;
  final bool enabled;
  final Future<void> Function(String, Map<String, Object>, {String? done})
  onSet;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = printer['name'] as String;
    final description = printer['description'] as String? ?? '';
    final location = printer['location'] as String? ?? '';
    final reason = printer['reason'] as String? ?? '';
    final isDefault = printer['default'] == true;
    final paused = printer['state'] == 'stopped';
    final jobs = (printer['jobs'] as List? ?? [])
        .cast<Map>()
        .map((j) => j.cast<String, dynamic>())
        .toList();
    final (statusIcon, statusLabel) = _status(printer);
    return SettingsSurface(
      key: ValueKey('printer-$name'),
      padding: .zero,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Padding(
            padding: const .fromLTRB(20, 20, 20, 12),
            child: Row(
              crossAxisAlignment: .start,
              spacing: 16,
              children: [
                const Icon(Icons.print_outlined, size: 32),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 4,
                    children: [
                      Text(
                        description.isEmpty ? name : description,
                        style: text.titleMedium,
                      ),
                      if (description.isNotEmpty && description != name)
                        Text('Queue: $name', style: text.bodySmall),
                      if (location.isNotEmpty)
                        Text('Location: $location', style: text.bodySmall),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _Fact(icon: statusIcon, label: statusLabel),
                          if (isDefault)
                            const _Fact(
                              icon: Icons.star_rounded,
                              label: 'Default',
                            ),
                          if (printer['accepting'] == false)
                            const _Fact(
                              icon: Icons.block_rounded,
                              label: 'Not accepting jobs',
                            ),
                        ],
                      ),
                      if (reason.isNotEmpty && reason != statusLabel)
                        Text(reason, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const .symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isDefault)
                  TextButton.icon(
                    onPressed: enabled
                        ? () => onSet(defaultPrinterId, {'name': name})
                        : null,
                    icon: const Icon(Icons.star_outline_rounded),
                    label: const Text('Set as default'),
                  ),
                TextButton.icon(
                  onPressed: enabled
                      ? () => onSet(printTestPageId, {
                          'name': name,
                        }, done: 'Test page sent to $name')
                      : null,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Print test page'),
                ),
                TextButton.icon(
                  onPressed: enabled
                      ? () => onSet(pausePrinterId, {
                          'name': name,
                          'paused': !paused,
                        })
                      : null,
                  icon: Icon(
                    paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  ),
                  label: Text(paused ? 'Resume' : 'Pause'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: enabled ? () => onRemove(name) : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Remove'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, indent: 20, endIndent: 20),
          if (jobs.isEmpty)
            Padding(
              padding: const .all(20),
              child: Text('No jobs waiting', style: text.bodyMedium),
            )
          else
            ExpansionTile(
              title: Text(
                jobs.length == 1
                    ? '1 job waiting'
                    : '${jobs.length} jobs waiting',
              ),
              leading: const Icon(Icons.queue_outlined),
              children: [
                for (final job in jobs)
                  ListTile(
                    title: Text(job['id'] as String),
                    subtitle: Text(
                      [
                        'User: ${job['user']}',
                        if (job['size'] case final int size)
                          'Size: ${(size / 1024).ceil()} KB',
                      ].join('\n'),
                    ),
                    trailing: TextButton(
                      onPressed: enabled
                          ? () => onSet(cancelPrintJobId, {
                              'id': job['id'] as String,
                            })
                          : null,
                      child: const Text('Cancel'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: 4,
    children: [
      Icon(icon, size: 18),
      Text(label, style: Theme.of(context).textTheme.labelLarge),
    ],
  );
}
