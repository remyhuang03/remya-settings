import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import '../../settings/presentation/settings_widgets.dart';

class BarAppearancePage extends StatefulWidget {
  const BarAppearancePage({
    super.key,
    required this.client,
    required this.page,
  });

  final SettingsClient client;
  final SettingsPageSpec page;

  @override
  State<BarAppearancePage> createState() => _BarAppearancePageState();
}

class _BarAppearancePageState extends State<BarAppearancePage> {
  bool? _showSeconds;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _update();
  }

  Future<void> _update([bool? enabled]) async {
    setState(() => _busy = true);
    try {
      final value = await (enabled == null
          ? widget.client.readBarClockSeconds()
          : widget.client.setBarClockSeconds(enabled));
      if (!mounted) return;
      setState(() {
        _showSeconds = value;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      if (_error case final error?)
        SettingsErrorCard(
          message: error,
          onRetry: _busy ? null : () => _update(),
        ),
      SettingsSectionCard(
        widget.page.sections.first,
        pageRows: const {},
        onPageRow: (_) {},
        controlBuilder: (setting) => SettingRow(
          id: setting.id,
          label: Text(
            setting.title,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          control: _showSeconds == null
              ? (_busy ? const CircularProgressIndicator() : null)
              : Semantics(
                  label: setting.title,
                  child: Switch(
                    value: _showSeconds!,
                    onChanged: _busy ? null : _update,
                  ),
                ),
        ),
      ),
      _FoldedTrayApps(client: widget.client),
    ],
  );
}

class _FoldedTrayApps extends StatefulWidget {
  const _FoldedTrayApps({required this.client});

  final SettingsClient client;

  @override
  State<_FoldedTrayApps> createState() => _FoldedTrayAppsState();
}

class _FoldedTrayAppsState extends State<_FoldedTrayApps> {
  late Future<Set<String>> _apps;
  late final StreamSubscription<SettingsChange> _changes;

  @override
  void initState() {
    super.initState();
    _apps = widget.client.readBarFoldedApps();
    _changes = widget.client.changes
        .where((change) => change.topic == barFoldedAppsSettingId)
        .listen((_) => _reload(), onError: (Object _) {});
  }

  void _reload() {
    setState(() => _apps = widget.client.readBarFoldedApps());
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      const SettingsSectionTitle('App tray'),
      SettingsSurface(
        padding: .zero,
        child: FutureBuilder<Set<String>>(
          future: _apps,
          builder: (context, snapshot) {
            final text = Theme.of(context).textTheme;
            return settingsRows([
              SettingRow(
                id: barFoldedAppsSettingId,
                label: Text(
                  'Folded apps are hidden from the bar. Fold an app from its tray menu, and pin it here to show it again.',
                  style: text.bodySmall,
                ),
              ),
              if (snapshot.connectionState != .done)
                const LinearProgressIndicator()
              else if (snapshot.hasError)
                SettingRow(
                  id: '$barFoldedAppsSettingId-error',
                  label: Text('${snapshot.error}', style: text.bodyMedium),
                  control: TextButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                )
              else if (snapshot.data!.isEmpty)
                SettingRow(
                  id: '$barFoldedAppsSettingId-empty',
                  label: Text('No folded apps', style: text.bodyLarge),
                )
              else
                for (final id in snapshot.data!.toList()..sort())
                  SettingRow(
                    id: '$barFoldedAppsSettingId-$id',
                    label: Text(id, style: text.bodyLarge),
                    control: FilledButton.tonalIcon(
                      onPressed: () => setState(
                        () => _apps = widget.client.setBarAppFolded(id, false),
                      ),
                      icon: const Icon(Icons.push_pin_outlined),
                      label: const Text('Pin to tray'),
                    ),
                  ),
            ]);
          },
        ),
      ),
    ],
  );
}
