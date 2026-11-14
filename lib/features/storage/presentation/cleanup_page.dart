import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../../applications/presentation/application_metadata.dart';
import '../application/storage_controller.dart';
import 'storage_widgets.dart';

class CleanupPage extends StatefulWidget {
  const CleanupPage({super.key, required this.controller});
  final StorageController controller;
  @override
  State<CleanupPage> createState() => _CleanupPageState();
}

class _CleanupPageState extends State<CleanupPage> {
  bool _trash = false, _packageCache = false, _uninstalled = false;
  final _folders = <String>{}, _packages = <String>{}, _files = <String>{};
  int _keep = 2;

  StorageController get c => widget.controller;
  Map part(String id) => c.cleanup[id] as Map? ?? {};
  List<Map> rows(String section, String key) =>
      (part(section)[key] as List? ?? []).cast<Map>();
  List<Map> get folders => rows('cache', 'folders');
  List<Map> get packages =>
      rows('orphans', 'packages').toList()
        ..sort((a, b) => (b['bytes'] as num).compareTo(a['bytes'] as num));
  List<Map> get files => rows('large_files', 'files');

  num _sum(List<Map> items, Set<String> chosen, String key) => items
      .where((i) => chosen.contains(i[key]))
      .fold<num>(0, (s, i) => s + (i['bytes'] as num));
  num get packageCacheBytes => math.min(
    part('package_cache')['bytes'] as num? ?? 0,
    ((part('package_cache')['candidates'] as Map?)?['$_keep'] as num? ?? 0) +
        (_uninstalled
            ? part('package_cache')['uninstalled_bytes'] as num? ?? 0
            : 0),
  );
  num get selectedBytes =>
      (_trash ? part('trash')['bytes'] as num? ?? 0 : 0) +
      _sum(folders, _folders, 'name') +
      (_packageCache ? packageCacheBytes : 0) +
      _sum(packages, _packages, 'name') +
      _sum(files, _files, 'path');
  bool get anySelected =>
      _trash ||
      _packageCache ||
      _folders.isNotEmpty ||
      _packages.isNotEmpty ||
      _files.isNotEmpty;

  @override
  void initState() {
    super.initState();
    c.reload();
  }

  List<String> get _permanent => [
    if (_trash) 'Trash: ${part('trash')['items'] ?? 0} items',
    for (final f in folders.where((f) => _folders.contains(f['name'])))
      'Cache folder: ${f['name']} (${formatBytes(f['bytes'] as num)})',
    if (_packageCache)
      'Package cache: keep $_keep latest versions${_uninstalled ? '; also remove versions of uninstalled packages' : ''}',
    for (final p in packages.where((p) => _packages.contains(p['name'])))
      'Package: ${p['name']} ${p['version']}',
  ];

  Future<void> _clean() async {
    final permanent = _permanent;
    final trashed = files
        .where((f) => _files.contains(f['path']))
        .map((f) => f['path'] as String)
        .toList();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => _ConfirmDialog(
        permanent: permanent,
        trashed: trashed,
        bytes: selectedBytes,
      ),
    );
    if (accepted != true || !mounted || c.busy) return;
    final before = (c.storage['usage'] as Map?)?['volume']?['free'] as num?;
    final actions = <(String, Object)>[
      if (_trash) ('cleanup.trash', {'action': 'empty'}),
      if (_folders.isNotEmpty)
        ('cleanup.cache', {'folders': _folders.toList()}),
      if (_packageCache)
        ('cleanup.package-cache', {'keep': _keep, 'uninstalled': _uninstalled}),
      if (_packages.isNotEmpty)
        (
          'cleanup.orphans',
          {
            'packages': [
              for (final p in packages.where(
                (p) => _packages.contains(p['name']),
              ))
                {'name': p['name'], 'version': p['version']},
            ],
          },
        ),
      if (_files.isNotEmpty) ('cleanup.large-files', {'paths': trashed}),
    ];
    for (final (id, payload) in actions) {
      if (!await c.change(id, payload)) return;
    }
    if (!mounted) return;
    final after = (c.storage['usage'] as Map?)?['volume']?['free'] as num?;
    setState(() {
      _trash = _packageCache = false;
      _folders.clear();
      _packages.clear();
      _files.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          before == null || after == null
              ? 'Cleanup completed'
              : 'Freed ${formatBytes(math.max(0, after - before))}',
        ),
      ),
    );
  }

  /// A checkbox that selects every item of a list: checked, mixed or empty.
  Widget _listCheckbox(Set<String> chosen, List<Map> items, String key) =>
      Checkbox(
        tristate: true,
        value: chosen.isEmpty
            ? false
            : chosen.length == items.length
            ? true
            : null,
        onChanged: c.busy || items.isEmpty
            ? null
            : (_) => setState(() {
                if (chosen.length == items.length) {
                  chosen.clear();
                } else {
                  chosen.addAll(items.map((i) => i[key] as String));
                }
              }),
      );

  void _pick(Set<String> chosen, String key, bool? value) =>
      setState(() => value == true ? chosen.add(key) : chosen.remove(key));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final theme = Theme.of(context);
      final trash = part('trash');
      final trashItems = trash['items'] as int? ?? 0;
      final broken = trash['broken'] as int? ?? 0;
      final cacheTotal = part('cache')['bytes'] as num? ?? 0;
      final largestFolder = folders.fold<num>(
        0,
        (m, f) => math.max(m, f['bytes'] as num),
      );
      final pc = part('package_cache');
      final recommendations = <Widget>[
        _Recommendation(
          key: const ValueKey('cleanup-trash'),
          icon: Icons.delete_outline_rounded,
          title: 'Trash',
          explanation: trashItems == 0
              ? 'The Trash is empty'
              : '$trashItems items will be permanently deleted',
          bytes: trashItems == 0 ? null : trash['bytes'] as num?,
          error: trash['error'] as String?,
          note: broken > 0
              ? '$broken damaged Trash entries on other drives were skipped'
              : null,
          checkbox: trashItems == 0
              ? null
              : Checkbox(
                  value: _trash,
                  onChanged: c.busy
                      ? null
                      : (v) => setState(() => _trash = v == true),
                ),
        ),
        _Recommendation(
          key: const ValueKey('cleanup-cache'),
          icon: Icons.folder_outlined,
          title: 'Cached files',
          explanation: 'Close the apps first; they rebuild their caches',
          bytes: cacheTotal,
          error: part('cache')['error'] as String?,
          checkbox: folders.isEmpty
              ? null
              : _listCheckbox(_folders, folders, 'name'),
          details: _ItemList(
            items: folders,
            itemBuilder: (f) => _ItemRow(
              checked: _folders.contains(f['name']),
              onChanged: c.busy
                  ? null
                  : (v) => _pick(_folders, f['name'] as String, v),
              title: f['name'] as String,
              bytes: f['bytes'] as num,
              share: largestFolder > 0
                  ? (f['bytes'] as num) / largestFolder
                  : 0,
            ),
          ),
        ),
        _Recommendation(
          key: const ValueKey('cleanup-package-cache'),
          icon: Icons.inventory_2_outlined,
          title: 'Package cache',
          explanation: 'Older downloaded package versions',
          bytes: packageCacheBytes,
          error: pc['missing_tool'] as String? ?? pc['error'] as String?,
          locked: true,
          checkbox: Checkbox(
            value: _packageCache,
            onChanged: c.busy
                ? null
                : (v) => setState(() => _packageCache = v == true),
          ),
          details: Column(
            crossAxisAlignment: .start,
            spacing: 12,
            children: [
              Row(
                spacing: 16,
                children: [
                  const Expanded(child: Text('Latest versions to keep')),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                    ],
                    selected: {_keep},
                    showSelectedIcon: false,
                    onSelectionChanged: c.busy
                        ? null
                        : (v) => setState(() => _keep = v.single),
                  ),
                ],
              ),
              Row(
                spacing: 16,
                children: [
                  Expanded(
                    child: Text(
                      'Also remove all versions of uninstalled packages '
                      '(${formatBytes(pc['uninstalled_bytes'] as num? ?? 0)})',
                    ),
                  ),
                  Switch(
                    value: _uninstalled,
                    onChanged: c.busy
                        ? null
                        : (v) => setState(() => _uninstalled = v),
                  ),
                ],
              ),
            ],
          ),
        ),
        _Recommendation(
          key: const ValueKey('cleanup-orphans'),
          icon: Icons.apps_rounded,
          title: 'Unused packages',
          explanation:
              '${packages.length} packages no longer required by anything',
          bytes: part('orphans')['bytes'] as num?,
          error: part('orphans')['error'] as String?,
          locked: true,
          checkbox: packages.isEmpty
              ? null
              : _listCheckbox(_packages, packages, 'name'),
          details: _ItemList(
            items: packages,
            itemBuilder: (p) => _ItemRow(
              checked: _packages.contains(p['name']),
              onChanged: c.busy
                  ? null
                  : (v) => _pick(_packages, p['name'] as String, v),
              title: p['name'] as String,
              subtitle: p['version'] as String,
              bytes: p['bytes'] as num,
            ),
          ),
        ),
        _Recommendation(
          key: const ValueKey('cleanup-large-files'),
          icon: Icons.description_outlined,
          title: 'Large files',
          explanation: 'Selected files move to the Trash',
          bytes: files.fold<num>(0, (s, f) => s + (f['bytes'] as num)),
          error: part('large_files')['error'] as String?,
          checkbox: files.isEmpty ? null : _listCheckbox(_files, files, 'path'),
          details: _ItemList(
            items: files,
            itemBuilder: (f) {
              final path = f['path'] as String;
              final folder = path.substring(0, path.lastIndexOf('/'));
              return _ItemRow(
                checked: _files.contains(path),
                onChanged: c.busy ? null : (v) => _pick(_files, path, v),
                title: path.split('/').last,
                subtitle: folder,
                date: StorageDate(
                  at: f['modified'] as int,
                  controller: c,
                  prefix: 'Modified ',
                  style: theme.textTheme.bodySmall,
                ),
                bytes: f['bytes'] as num,
                trailing: IconButton(
                  tooltip: 'Show in folder',
                  icon: const Icon(Icons.folder_open_outlined),
                  onPressed: c.busy
                      ? null
                      : () => c.change('storage.open', {'path': folder}),
                ),
              );
            },
          ),
        ),
      ];
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          if (c.errorMessage case final error?)
            SettingsErrorCard(
              message: error,
              onRetry: c.busy ? null : c.reload,
            ),
          _CleanupHero(
            state: c.cleanup,
            scanning: c.cleanup['scanning'] == true,
          ),
          const SettingsSectionTitle('Cleanup recommendations'),
          SettingsSurface(
            padding: .zero,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                settingsRows(recommendations),
                const Divider(height: 1),
                Padding(
                  padding: const .symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    spacing: 16,
                    children: [
                      Expanded(
                        child: Text(
                          anySelected
                              ? '${formatBytes(selectedBytes)} selected'
                              : 'Select items to clean up',
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      if (c.busy)
                        const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      FilledButton.icon(
                        key: const ValueKey('cleanup-run'),
                        onPressed: c.busy || !anySelected ? null : _clean,
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Clean up'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SettingsSectionTitle('Automatic cleanup'),
          _AutomaticCleanup(controller: c),
        ],
      );
    },
  );
}

class _CleanupHero extends StatelessWidget {
  const _CleanupHero({required this.state, required this.scanning});
  final Map state;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = storageColors(theme.colorScheme);
    final total = state['reclaimable_bytes'] as num? ?? 0;
    final entries = <(String, num, Color)>[
      ('Cached files', state['cache']?['bytes'] as num? ?? 0, palette[1]),
      ('Unused packages', state['orphans']?['bytes'] as num? ?? 0, palette[2]),
      (
        'Package cache',
        state['package_cache']?['candidates']?['2'] as num? ?? 0,
        palette[0],
      ),
      ('Trash', state['trash']?['bytes'] as num? ?? 0, palette[3]),
    ].where((e) => e.$2 > 0).toList();
    final donut = SizedBox.square(
      dimension: 168,
      child: Stack(
        alignment: .center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              centerSpaceRadius: 58,
              sectionsSpace: 2,
              sections: [
                if (entries.isEmpty)
                  PieChartSectionData(
                    value: 1,
                    color: theme.colorScheme.surfaceContainerHighest,
                    showTitle: false,
                    radius: 22,
                  ),
                for (final (_, bytes, color) in entries)
                  PieChartSectionData(
                    value: bytes.toDouble(),
                    color: color,
                    showTitle: false,
                    radius: 22,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: .min,
            children: [
              Text(formatBytes(total), style: theme.textTheme.titleLarge),
              Text(
                'can be freed',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final text = Column(
      crossAxisAlignment: .stretch,
      children: [
        Text('Free up space', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          scanning ? 'Measuring your files…' : 'Choose what to remove below. Package cleanup asks for administrator authorization.',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        for (final (label, bytes, color) in entries)
          StorageLegend(label: label, bytes: bytes, color: color, total: total),
      ],
    );
    return SettingsSurface(
      padding: const .all(24),
      child: LayoutBuilder(
        builder: (_, constraints) => constraints.maxWidth < 560
            ? Column(spacing: 16, children: [donut, text])
            : Row(
                spacing: 32,
                children: [
                  donut,
                  Expanded(child: text),
                ],
              ),
      ),
    );
  }
}

/// One recommendation: selection, summary and size; expands to its details.
class _Recommendation extends StatefulWidget {
  const _Recommendation({
    super.key,
    required this.icon,
    required this.title,
    required this.explanation,
    required this.bytes,
    this.checkbox,
    this.details,
    this.error,
    this.note,
    this.locked = false,
  });
  final IconData icon;
  final String title, explanation;
  final num? bytes;
  final Widget? checkbox, details;
  final String? error, note;
  final bool locked;

  @override
  State<_Recommendation> createState() => _RecommendationState();
}

class _RecommendationState extends State<_Recommendation> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final error = widget.error;
    final expandable = widget.details != null && error == null;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        InkWell(
          onTap: expandable
              ? () => setState(() => _expanded = !_expanded)
              : null,
          child: Padding(
            padding: const .fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: error == null ? widget.checkbox : null,
                ),
                Icon(widget.icon, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(widget.title, style: theme.textTheme.bodyLarge),
                      if (error != null)
                        Row(
                          spacing: 6,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: theme.colorScheme.error,
                            ),
                            Expanded(child: Text(error, style: muted)),
                          ],
                        )
                      else
                        Text(widget.explanation, style: muted),
                      if (widget.note case final note?)
                        Text(note, style: muted),
                      if (widget.locked && error == null)
                        Row(
                          spacing: 6,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            Text(
                              'Requires administrator authorization',
                              style: muted,
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (error == null && widget.bytes != null)
                  Padding(
                    padding: const .only(left: 16),
                    child: Text(
                      formatBytes(widget.bytes!),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                SizedBox(
                  width: 48,
                  child: expandable
                      ? IconButton(
                          tooltip: _expanded
                              ? 'Hide ${widget.title.toLowerCase()}'
                              : 'Show ${widget.title.toLowerCase()}',
                          onPressed: () =>
                              setState(() => _expanded = !_expanded),
                          icon: AnimatedRotation(
                            turns: _expanded ? .5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(Icons.expand_more_rounded),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: .topCenter,
          child: _expanded && expandable
              ? Padding(
                  padding: const .fromLTRB(60, 0, 20, 16),
                  child: widget.details,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// The largest items first, with the rest one click away.
class _ItemList extends StatefulWidget {
  const _ItemList({required this.items, required this.itemBuilder});
  final List<Map> items;
  final Widget Function(Map) itemBuilder;
  @override
  State<_ItemList> createState() => _ItemListState();
}

class _ItemListState extends State<_ItemList> {
  static const _preview = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) return const Text('Nothing to clean up');
    final shown = _all ? items : items.take(_preview);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: .circular(16),
      clipBehavior: .antiAlias,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final item in shown) widget.itemBuilder(item),
          if (items.length > _preview)
            Align(
              alignment: .centerLeft,
              child: Padding(
                padding: const .all(4),
                child: TextButton(
                  onPressed: () => setState(() => _all = !_all),
                  child: Text(_all ? 'Show fewer' : 'Show all ${items.length}'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.checked,
    required this.onChanged,
    required this.title,
    required this.bytes,
    this.subtitle,
    this.date,
    this.share,
    this.trailing,
  });
  final bool checked;
  final ValueChanged<bool?>? onChanged;
  final String title;
  final String? subtitle;
  final Widget? date, trailing;
  final num bytes;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged!(!checked),
      child: Padding(
        padding: const .symmetric(horizontal: 4, vertical: 4),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Checkbox(value: checked, onChanged: onChanged),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(title, overflow: .ellipsis),
                    if (subtitle case final subtitle?)
                      Text(subtitle, style: muted, overflow: .ellipsis),
                    ?date,
                  ],
                ),
              ),
              // The proportion bar is a wide-window extra; size stays readable.
              if (share != null && constraints.maxWidth >= 480)
                Padding(
                  padding: const .only(left: 16),
                  child: SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 6,
                      borderRadius: .circular(3),
                    ),
                  ),
                ),
              SizedBox(
                width: 80,
                child: Text(formatBytes(bytes), textAlign: .end),
              ),
              if (trailing case final trailing?)
                trailing
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.permanent,
    required this.trashed,
    required this.bytes,
  });
  final List<String> permanent, trashed;
  final num bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget group(String title, List<String> items) => Column(
      crossAxisAlignment: .start,
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        for (final item in items)
          Padding(
            padding: const .symmetric(vertical: 2),
            child: Text(item, style: theme.textTheme.bodyMedium),
          ),
      ],
    );
    return AlertDialog(
      icon: const Icon(Icons.cleaning_services_outlined),
      title: Text('Clean up ${formatBytes(bytes)}?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: .start,
            mainAxisSize: .min,
            spacing: 16,
            children: [
              if (permanent.isNotEmpty) group('Permanently delete', permanent),
              if (trashed.isNotEmpty) group('Move to Trash', trashed),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Clean up'),
        ),
      ],
    );
  }
}

class _AutomaticCleanup extends StatelessWidget {
  const _AutomaticCleanup({required this.controller});
  final StorageController controller;

  Widget _choice(
    BuildContext context,
    String id,
    String label,
    Object? value,
    Map<Object, String> options,
  ) => SettingRow(
    id: id,
    label: Text(label, style: Theme.of(context).textTheme.bodyLarge),
    control: DropdownMenu<Object>(
      key: ValueKey('$id-$value'),
      width: 232,
      initialSelection: value,
      enabled: controller.policyWritable,
      dropdownMenuEntries: [
        for (final e in options.entries)
          DropdownMenuEntry(value: e.key, label: e.value),
      ],
      onSelected: (v) {
        if (v != null && v != value) controller.change(id, v);
      },
    ),
  );

  Map<Object, String> _days(List<int> values) => {
    for (final d in values)
      d: switch (d) {
        0 => 'Never',
        1 => 'After 1 day',
        _ => 'After $d days',
      },
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final a = c.cleanup['automatic'] as Map?;
    if (a == null) {
      return const SettingsSurface(child: Text('Reading cleanup preferences…'));
    }
    final enabled = a['enabled'] == true;
    final last = c.cleanup['last_run'] as Map?;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final lastRun = last == null
        ? <Widget>[Text('Not run yet', style: muted)]
        : [
            StorageDate(
              at: last['at'] as int,
              controller: c,
              prefix: 'Last run ',
              style: muted,
            ),
            Text(
              'Freed ${formatBytes(last['freed_bytes'] as num)}',
              style: muted,
            ),
            if (last['error'] case final String error)
              Text(
                error,
                style: muted?.copyWith(color: theme.colorScheme.error),
              ),
          ];
    return SettingsSurface(
      padding: .zero,
      child: settingsRows([
        SettingRow(
          id: 'cleanup.auto',
          label: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Text('Clean up automatically', style: theme.textTheme.bodyLarge),
              Text(
                'Remove old files from the Trash, caches and Downloads. Packages are never removed automatically.',
                style: muted,
              ),
            ],
          ),
          control: Switch(
            value: enabled,
            onChanged: c.policyWritable
                ? (v) => c.change('cleanup.auto', v)
                : null,
          ),
        ),
        if (enabled) ...[
          _choice(context, 'cleanup.auto-frequency', 'Run', a['frequency'], {
            'low-space': 'When space is low',
            'daily': 'Every day',
            'weekly': 'Every week',
            'monthly': 'Every month',
          }),
          _choice(
            context,
            'cleanup.auto-trash',
            'Delete files in the Trash',
            a['trash_days'],
            _days([0, 1, 14, 30, 60]),
          ),
          _choice(
            context,
            'cleanup.auto-cache',
            'Delete unused cached files',
            a['cache_days'],
            _days([0, 30, 60, 90]),
          ),
          _choice(
            context,
            'cleanup.auto-downloads',
            'Move unused downloads to the Trash',
            a['downloads_days'],
            _days([0, 30, 60, 90]),
          ),
          SettingRow(
            id: 'cleanup.run-now',
            label: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text('Run cleanup now', style: theme.textTheme.bodyLarge),
                ...lastRun,
              ],
            ),
            control: FilledButton.tonalIcon(
              onPressed: c.policyWritable
                  ? () => c.change('cleanup.run-now', {})
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Run now'),
            ),
          ),
        ] else if (last != null)
          SettingRow(
            id: 'cleanup.last-run',
            label: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(
                  'Last automatic cleanup',
                  style: theme.textTheme.bodyLarge,
                ),
                ...lastRun,
              ],
            ),
          ),
      ]),
    );
  }
}
