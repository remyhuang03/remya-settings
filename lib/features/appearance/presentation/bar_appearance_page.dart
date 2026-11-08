import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import 'bar_pill_layout.dart';

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
  bool? _keyboardPreview;
  BarLayout? _layout;
  bool _busy = true;
  String? _error;
  late final StreamSubscription<SettingsChange> _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.client.changes.listen((change) {
      if (change.topic == barLayoutSettingId) {
        unawaited(_load());
      } else if (change.value['value'] case final bool enabled
          when change.topic == barKeyboardPreviewSettingId) {
        setState(() => _keyboardPreview = enabled);
      }
    }, onError: (Object _) {});
    _load();
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) setState(() => _error = null);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
    final (seconds, layout, preview) = await (
      widget.client.readBarClockSeconds(),
      widget.client.readBarLayout(),
      widget.client.readBarKeyboardPreview(),
    ).wait;
    if (mounted) {
      setState(() {
        _showSeconds = seconds;
        _layout = layout;
        _keyboardPreview = preview;
      });
    }
  });

  Future<void> _setSeconds(bool enabled) => _run(() async {
    final value = await widget.client.setBarClockSeconds(enabled);
    if (mounted) setState(() => _showSeconds = value);
  });

  Future<void> _setKeyboardPreview(bool enabled) => _run(() async {
    final value = await widget.client.setBarKeyboardPreview(enabled);
    if (mounted) setState(() => _keyboardPreview = value);
  });

  // The service keeps the last valid layout; a rejected edit leaves it shown.
  Future<void> _setLayout(BarLayout layout) => _run(() async {
    final value = await widget.client.setBarLayout(layout);
    if (mounted) setState(() => _layout = value);
  });

  @override
  Widget build(BuildContext context) {
    final layout = _layout;
    final sections = widget.page.sections;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (_error case final error?)
          SettingsErrorCard(message: error, onRetry: _busy ? null : _load),
        SettingsSectionTitle(sections[0].title),
        if (layout == null)
          const LinearProgressIndicator()
        else
          BarPillLayoutEditor(
            layout: layout,
            showSeconds: _showSeconds ?? true,
            onChanged: _busy ? null : _setLayout,
          ),
        if (layout != null)
          _PillOptions(
            title: sections[1].title,
            secondsTitle: sections[1].controls.first.title,
            layout: layout,
            showSeconds: _showSeconds,
            onSeconds: _busy ? null : _setSeconds,
            onLayout: _busy ? null : _setLayout,
          ),
        _FoldedTrayApps(client: widget.client),
        if (_keyboardPreview case final preview?) ...[
          SettingsSectionTitle(sections[3].title),
          SettingRow(
            id: barKeyboardPreviewSettingId,
            label: Text(sections[3].controls.single.title),
            control: Switch(
              value: preview,
              onChanged: _busy ? null : _setKeyboardPreview,
            ),
          ),
        ],
      ],
    );
  }
}

/// Options of visible pills; options of hidden pills are omitted.
class _PillOptions extends StatelessWidget {
  const _PillOptions({
    required this.title,
    required this.secondsTitle,
    required this.layout,
    required this.showSeconds,
    required this.onSeconds,
    required this.onLayout,
  });

  final String title;
  final String secondsTitle;
  final BarLayout layout;
  final bool? showSeconds;
  final ValueChanged<bool>? onSeconds;
  final ValueChanged<BarLayout>? onLayout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hidden = layout.hidden;
    Widget label(String pill, String option) => Row(
      spacing: 16,
      children: [
        BarPillSample(
          id: pill,
          layout: layout,
          showSeconds: showSeconds ?? true,
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(option, style: text.bodyLarge),
              Text(barPillNames[pill]!, style: text.bodySmall),
            ],
          ),
        ),
      ],
    );
    final rows = [
      if (!hidden.contains('clock') && showSeconds != null)
        SettingRow(
          id: barClockSecondsSettingId,
          label: label('clock', secondsTitle),
          control: Semantics(
            label: secondsTitle,
            child: Switch(value: showSeconds!, onChanged: onSeconds),
          ),
        ),
      if (!hidden.contains('workspaces'))
        SettingRow(
          id: '$barLayoutSettingId-workspaces',
          label: label('workspaces', 'Workspaces shown'),
          control: DropdownMenu<int>(
            key: ValueKey(layout.workspaceCount),
            width: 112,
            enabled: onLayout != null,
            initialSelection: layout.workspaceCount,
            label: const Text('Count'),
            onSelected: (count) {
              if (count != null) {
                onLayout?.call(layout.copyWith(workspaceCount: count));
              }
            },
            dropdownMenuEntries: [
              for (var count = 1; count <= 10; count++)
                DropdownMenuEntry(value: count, label: '$count'),
            ],
          ),
        ),
      if (!hidden.contains('resources'))
        SettingRow(
          id: '$barLayoutSettingId-resources',
          label: label('resources', 'Shown metrics'),
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final id in barResourceIds)
                FilterChip(
                  label: Text(barResourceNames[id]!),
                  selected: layout.resources.contains(id),
                  // At least one metric stays; hide the pill to remove it.
                  onSelected:
                      onLayout == null ||
                          layout.resources.length == 1 &&
                              layout.resources.contains(id)
                      ? null
                      : (selected) => onLayout!(
                          layout.copyWith(
                            resources: [
                              for (final metric in barResourceIds)
                                if (metric == id
                                    ? selected
                                    : layout.resources.contains(metric))
                                  metric,
                            ],
                          ),
                        ),
                ),
            ],
          ),
        ),
      if (!hidden.contains('window'))
        SettingRow(
          id: '$barLayoutSettingId-window',
          label: label('window', 'Show app name'),
          control: Semantics(
            label: 'Show app name',
            child: Switch(
              value: layout.windowAppName,
              onChanged: onLayout == null
                  ? null
                  : (value) => onLayout!(layout.copyWith(windowAppName: value)),
            ),
          ),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SettingsSectionTitle(title),
        SettingsSurface(padding: .zero, child: settingsRows(rows)),
      ],
    );
  }
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
