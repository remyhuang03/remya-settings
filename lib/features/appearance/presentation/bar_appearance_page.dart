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
        SettingsSurface(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(error),
              TextButton(
                onPressed: _busy ? null : () => _update(),
                child: const Text('Retry'),
              ),
            ],
          ),
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
  Widget build(BuildContext context) => SettingsSurface(
    child: FutureBuilder<Set<String>>(
      future: _apps,
      builder: (context, snapshot) => Column(
        crossAxisAlignment: .start,
        children: [
          Text('App tray', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Fold apps from their tray menu. Pin them here to keep them visible.',
          ),
          if (snapshot.connectionState != .done)
            const LinearProgressIndicator()
          else if (snapshot.hasError)
            TextButton(onPressed: _reload, child: const Text('Retry'))
          else if (snapshot.data!.isEmpty)
            const Padding(padding: .only(top: 8), child: Text('No folded apps'))
          else
            for (final id in snapshot.data!.toList()..sort())
              ListTile(
                contentPadding: .zero,
                title: Text(id),
                trailing: TextButton(
                  onPressed: () => setState(
                    () => _apps = widget.client.setBarAppFolded(id, false),
                  ),
                  child: const Text('Pin to tray'),
                ),
              ),
        ],
      ),
    ),
  );
}
