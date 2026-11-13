import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';

/// A Settings rule or a live one from another configuration file.
typedef WorkspaceRule = ({
  String workspace,
  String monitor,
  bool isDefault,
  bool persistent,
  String defaultName,
});

WorkspaceRule _rule(Map<String, dynamic> m) => (
  workspace: m['workspace'] as String? ?? '',
  monitor: m['monitor'] as String? ?? '',
  isDefault: m['default'] == true,
  persistent: m['persistent'] == true,
  defaultName: m['default_name'] as String? ?? '',
);

/// How people read a workspace selector.
String workspaceLabel(String selector) => switch (selector) {
  _ when selector.startsWith('name:') => selector.substring(5),
  _ when selector.startsWith('special:') =>
    'Scratchpad ${selector.substring(8)}',
  _ => 'Workspace $selector',
};

/// The rule selector of a live workspace from `hyprctl workspaces`.
String _selector(Map<String, dynamic> workspace) {
  final name = workspace['name'] as String? ?? '';
  return switch (workspace['id']) {
    final int id when id > 0 => '$id',
    _ when name.startsWith('special:') => name,
    _ => 'name:$name',
  };
}

/// Which workspaces each display starts with and keeps, and how the scratchpad behaves.
class WorkspacesPage extends StatefulWidget {
  const WorkspacesPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends State<WorkspacesPage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: 'desktop',
  )..reload();
  final _dragging = <String, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<WorkspaceRule> get _own => [
    for (final r in _controller.list('rules')) _rule(r),
  ];

  /// Live rules that come from the user's other configuration files.
  List<WorkspaceRule> get _foreign => [
    for (final r in _controller.list('live_rules'))
      if (r['settings'] != true) _rule(r),
  ];

  List<String> get _monitors => [
    for (final m in _controller.list('monitors')) m['name'] as String,
  ];

  void _edit({WorkspaceRule? initial, String? workspace, String? monitor}) =>
      showDialog<void>(
        context: context,
        builder: (_) => _RuleDialog(
          controller: _controller,
          monitors: _monitors,
          initial: initial,
          workspace: workspace,
          monitor: monitor,
        ),
      );

  void _select(String workspace, String monitor) {
    if (!_controller.canChange) return;
    final own = _own.where((r) => r.workspace == workspace).firstOrNull;
    own == null
        ? _edit(workspace: workspace, monitor: monitor)
        : _edit(initial: own);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final rows = InputRows(
        context,
        _controller,
        _dragging,
        (id, value) => setState(
          () => value == null ? _dragging.remove(id) : _dragging[id] = value,
        ),
      );
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        conflictTitle: 'Desktop settings differ from saved Settings',
        hero: InputHero(
          caption:
              'Each display with its workspaces. The highlighted one is '
              'showing now; select a workspace to change how it is kept.',
          child: _DisplayMap(
            monitors: _controller.list('monitors'),
            workspaces: _controller.list('workspaces'),
            rules: [..._foreign, ..._own],
            onSelect: _controller.canChange ? _select : null,
          ),
        ),
        isVisible: (setting) => setting.id != removeWorkspaceRuleId,
        controlBuilder: (setting) => switch (setting.id) {
          setWorkspaceRuleId => _rules(setting),
          'workspaces.initial-workspace-tracking' => rows.build(
            setting,
            subtitle:
                'Helps apps that open slowly after you switch away. Every '
                'window also covers the windows an app opens later',
          ),
          'workspaces.special-fallthrough' => rows.build(
            setting,
            subtitle: 'Clicks reach the workspace behind floating windows',
          ),
          _ => rows.build(setting),
        },
      );
    },
  );

  Widget _rules(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
    final own = _own;
    final foreign = _foreign;
    final canChange = _controller.canChange;
    return Column(
      key: ValueKey(setting.id),
      crossAxisAlignment: .stretch,
      children: [
        SettingRow(
          id: '${setting.id}-header',
          label: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Text(setting.title, style: text.bodyLarge),
              Text(
                own.isEmpty
                    ? 'Choose a display for a workspace, keep it when empty, '
                          'or start a display on it.'
                    : 'Changes reload the desktop configuration.',
                style: text.bodySmall,
              ),
            ],
          ),
          control: FilledButton.icon(
            key: const ValueKey('workspace-rule-add'),
            onPressed: canChange ? _edit : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ),
        for (final rule in own)
          _RuleRow(
            rule: rule,
            actions: [
              IconButton(
                tooltip: 'Edit',
                onPressed: canChange ? () => _edit(initial: rule) : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: canChange
                    ? () => _controller.set(removeWorkspaceRuleId, {
                        'workspace': rule.workspace,
                      })
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        if (foreign.isNotEmpty) ...[
          Padding(
            padding: const .fromLTRB(20, 16, 20, 4),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text('From your other configuration', style: text.titleSmall),
                Text(
                  'Settings shows these rules but does not change them.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          for (final rule in foreign) _RuleRow(rule: rule, actions: const []),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

/// The facts a rule sets, as a readable sentence fragment list.
String _facts(WorkspaceRule rule) => [
  if (rule.monitor.isNotEmpty) 'On ${rule.monitor}',
  if (rule.isDefault) 'Display starts here',
  if (rule.persistent) 'Kept when empty',
  if (rule.defaultName.isNotEmpty) 'Named ${rule.defaultName}',
].join(', ');

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.rule, required this.actions});
  final WorkspaceRule rule;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final facts = _facts(rule);
    return Padding(
      key: ValueKey('workspace-rule-${rule.workspace}'),
      padding: const .symmetric(horizontal: 20, vertical: 8),
      child: Row(
        spacing: 12,
        children: [
          Icon(
            rule.workspace.startsWith('special:')
                ? Icons.layers_outlined
                : Icons.desktop_windows_outlined,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(workspaceLabel(rule.workspace), style: text.bodyLarge),
                Text(
                  facts.isEmpty ? 'No changes' : facts,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Displays at their desktop positions and proportions, with their workspaces.
class _DisplayMap extends StatelessWidget {
  const _DisplayMap({
    required this.monitors,
    required this.workspaces,
    required this.rules,
    required this.onSelect,
  });
  final List<Map<String, dynamic>> monitors;
  final List<Map<String, dynamic>> workspaces;

  /// Later rules for the same workspace win, as Settings' file loads last.
  final List<WorkspaceRule> rules;
  final void Function(String workspace, String monitor)? onSelect;

  static double _n(Object? v) => (v as num? ?? 0).toDouble();

  @override
  Widget build(BuildContext context) {
    if (monitors.isEmpty) {
      return Text(
        'No display is reported.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final bounds = monitors
        .map(
          (m) => Rect.fromLTWH(
            _n(m['x']),
            _n(m['y']),
            math.max(_n(m['width']), 1),
            math.max(_n(m['height']), 1),
          ),
        )
        .reduce((a, b) => a.expandToInclude(b));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, 640.0);
        final scale = math.min(width / bounds.width, 260 / bounds.height);
        return SizedBox(
          width: bounds.width * scale,
          height: bounds.height * scale,
          child: Stack(
            children: [
              for (final m in monitors)
                Positioned(
                  left: (_n(m['x']) - bounds.left) * scale,
                  top: (_n(m['y']) - bounds.top) * scale,
                  width: _n(m['width']) * scale,
                  height: _n(m['height']) * scale,
                  child: Padding(
                    padding: const .all(3),
                    child: _Display(
                      monitor: m,
                      entries: _entries(m),
                      onSelect: onSelect,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Live workspaces on [monitor], then rule workspaces bound to it but not open.
  List<_Entry> _entries(Map<String, dynamic> monitor) {
    final name = monitor['name'] as String;
    final ruleOf = <String, WorkspaceRule>{
      for (final r in rules) r.workspace: r,
    };
    final shown = <String>{};
    final entries = <_Entry>[];
    for (final w in workspaces.where((w) => w['monitor'] == name)) {
      final selector = _selector(w);
      shown.add(selector);
      final label = w['name'] as String? ?? selector;
      entries.add((
        selector: selector,
        label: label.startsWith('special:') ? workspaceLabel(label) : label,
        active: [
          monitor['active_workspace'],
          monitor['special_workspace'],
        ].contains(w['name']),
        open: true,
        rule: ruleOf[selector],
      ));
    }
    for (final r in rules.where((r) => r.monitor == name)) {
      if (!shown.add(r.workspace)) continue;
      entries.add((
        selector: r.workspace,
        label: r.workspace.startsWith('name:')
            ? r.workspace.substring(5)
            : r.workspace.startsWith('special:')
            ? workspaceLabel(r.workspace)
            : r.defaultName.isNotEmpty
            ? r.defaultName
            : r.workspace,
        active: false,
        open: false,
        rule: ruleOf[r.workspace],
      ));
    }
    return entries;
  }
}

typedef _Entry = ({
  String selector,
  String label,
  bool active,
  bool open,
  WorkspaceRule? rule,
});

class _Display extends StatelessWidget {
  const _Display({
    required this.monitor,
    required this.entries,
    required this.onSelect,
  });
  final Map<String, dynamic> monitor;
  final List<_Entry> entries;
  final void Function(String workspace, String monitor)? onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = monitor['name'] as String;
    return Semantics(
      container: true,
      label: 'Display $name',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: .circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: .circular(12),
          child: Padding(
            padding: const .all(8),
            child: Column(
              crossAxisAlignment: .start,
              spacing: 6,
              children: [
                Text(
                  name,
                  style: text.labelLarge,
                  maxLines: 1,
                  overflow: .ellipsis,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final e in entries)
                          _WorkspaceChip(
                            entry: e,
                            onPressed: onSelect == null
                                ? null
                                : () => onSelect!(e.selector, name),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceChip extends StatelessWidget {
  const _WorkspaceChip({required this.entry, required this.onPressed});
  final _Entry entry;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rule = entry.rule;
    final facts = rule == null ? '' : _facts(rule);
    return Tooltip(
      message: [
        workspaceLabel(entry.selector),
        if (entry.active) 'Showing now',
        if (!entry.open) 'Not open',
        if (facts.isNotEmpty) facts,
      ].join('\n'),
      child: ActionChip(
        key: ValueKey('workspace-chip-${entry.selector}'),
        visualDensity: .compact,
        materialTapTargetSize: .shrinkWrap,
        avatar: rule == null
            ? null
            : Icon(
                rule.isDefault
                    ? Icons.home_outlined
                    : rule.persistent
                    ? Icons.push_pin_outlined
                    : Icons.rule_rounded,
                size: 16,
              ),
        label: Text(entry.label),
        backgroundColor: entry.active ? colors.secondaryContainer : null,
        side: entry.open
            ? null
            : BorderSide(color: colors.outline, style: .solid),
        onPressed: onPressed,
      ),
    );
  }
}

enum _Kind { number, named, scratchpad }

/// Creates or edits one Settings workspace rule.
class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.controller,
    required this.monitors,
    this.initial,
    this.workspace,
    this.monitor,
  });
  final FeatureOptionsController controller;
  final List<String> monitors;
  final WorkspaceRule? initial;
  final String? workspace;
  final String? monitor;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final String _start =
      widget.initial?.workspace ?? widget.workspace ?? '';
  late _Kind _kind = _start.startsWith('special:')
      ? .scratchpad
      : _start.startsWith('name:')
      ? .named
      : .number;
  late final _name = TextEditingController(
    text: _start.contains(':') ? _start.split(':').skip(1).join(':') : _start,
  );
  late final _defaultName = TextEditingController(
    text: widget.initial?.defaultName,
  );
  late String _monitor = widget.initial?.monitor ?? widget.monitor ?? '';
  late bool _persistent = widget.initial?.persistent ?? false;
  late bool _isDefault = widget.initial?.isDefault ?? false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _defaultName.dispose();
    super.dispose();
  }

  String get _workspace => switch (_kind) {
    .number => _name.text.trim(),
    .named => 'name:${_name.text.trim()}',
    .scratchpad => 'special:${_name.text.trim()}',
  };

  bool get _canStart => _kind != .scratchpad && _monitor.isNotEmpty;

  Future<void> _save() async {
    final ok = await widget.controller.set(setWorkspaceRuleId, {
      'workspace': _workspace,
      'monitor': _monitor,
      'default': _canStart && _isDefault,
      'persistent': _persistent,
      'default_name': _kind == .number ? _defaultName.text.trim() : '',
      'previous': widget.initial?.workspace,
    });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _error = widget.controller.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final monitors = [
      ...widget.monitors,
      if (_monitor.isNotEmpty && !widget.monitors.contains(_monitor)) _monitor,
    ];
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Add a workspace rule' : 'Edit workspace rule',
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              SegmentedButton<_Kind>(
                key: const ValueKey('workspace-kind'),
                segments: const [
                  ButtonSegment(value: .number, label: Text('Numbered')),
                  ButtonSegment(value: .named, label: Text('Named')),
                  ButtonSegment(value: .scratchpad, label: Text('Scratchpad')),
                ],
                selected: {_kind},
                showSelectedIcon: false,
                onSelectionChanged: (next) =>
                    setState(() => _kind = next.first),
              ),
              TextField(
                key: const ValueKey('workspace-name'),
                controller: _name,
                autofocus: true,
                keyboardType: _kind == .number ? .number : .text,
                decoration: InputDecoration(
                  labelText: _kind == .number ? 'Workspace number' : 'Name',
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              DropdownMenu<String>(
                key: const ValueKey('workspace-monitor'),
                expandedInsets: .zero,
                label: const Text('Display'),
                initialSelection: _monitor,
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: '', label: 'Any display'),
                  for (final m in monitors)
                    DropdownMenuEntry(value: m, label: m),
                ],
                onSelected: (next) => setState(() => _monitor = next ?? ''),
              ),
              SwitchListTile(
                key: const ValueKey('workspace-persistent'),
                contentPadding: .zero,
                title: const Text('Keep when empty'),
                subtitle: const Text(
                  'The workspace stays available after its last window closes',
                ),
                value: _persistent,
                onChanged: (next) => setState(() => _persistent = next),
              ),
              if (_canStart)
                SwitchListTile(
                  key: const ValueKey('workspace-default'),
                  contentPadding: .zero,
                  title: const Text('Show first on this display'),
                  subtitle: const Text(
                    'The display opens on this workspace when it turns on',
                  ),
                  value: _isDefault,
                  onChanged: (next) => setState(() => _isDefault = next),
                ),
              if (_kind == .number)
                TextField(
                  key: const ValueKey('workspace-default-name'),
                  controller: _defaultName,
                  decoration: const InputDecoration(
                    labelText: 'Name shown for this workspace (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              if (_error case final error?)
                Text(
                  error,
                  style: text.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('workspace-rule-save'),
          onPressed: _name.text.trim().isEmpty ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
