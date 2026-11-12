import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../../workspaces/presentation/workspaces_page.dart' show workspaceLabel;

/// A Settings window rule, keyed by what it matches.
typedef _Rule = Map<String, dynamic>;

String _match(_Rule r) => [
  if ((r['class'] as String? ?? '').isNotEmpty) r['class'] as String,
  if ((r['title'] as String? ?? '').isNotEmpty)
    'Title contains “${r['title']}”',
].join('\n');

/// What a rule does, as short facts.
List<String> _facts(_Rule r) {
  final size = r['size'] as List?;
  final workspace = r['workspace'] as String? ?? '';
  return [
    if (r['float'] == true) 'Floating',
    if (r['center'] == true) 'Centered',
    if (size != null) '${size[0]}% × ${size[1]}% of the display',
    if (workspace.isNotEmpty)
      r['silent'] == true
          ? 'Opens on ${workspaceLabel(workspace)} in the background'
          : 'Opens on ${workspaceLabel(workspace)}',
    if (r['pin'] == true) 'On every workspace',
    if (r['maximize'] == true) 'Maximized',
    if (r['fullscreen'] == true) 'Full screen',
    if (r['no_initial_focus'] == true) 'Does not take focus',
    if (r['opacity'] case final int o) 'Opacity $o%',
    if (r['no_blur'] == true) 'No blur',
    if (r['no_shadow'] == true) 'No shadow',
    if (r['keep_aspect_ratio'] == true) 'Keeps its aspect ratio',
    if (r['idle_inhibit'] case final String i when i.isNotEmpty)
      'Keeps the screen awake ${(_idle[i] ?? i).toLowerCase()}',
  ];
}

const _idle = {
  'focus': 'While focused',
  'fullscreen': 'While full screen',
  'always': 'While open',
};

/// How chosen apps' windows open and look.
class WindowRulesPage extends StatefulWidget {
  const WindowRulesPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<WindowRulesPage> createState() => _WindowRulesPageState();
}

class _WindowRulesPageState extends State<WindowRulesPage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: 'desktop',
  )..reload();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit([_Rule? initial]) => showDialog<void>(
    context: context,
    builder: (_) => _RuleDialog(
      controller: _controller,
      windows: _controller.list('windows'),
      initial: initial,
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => InputPageFrame(
      catalog: widget.catalog,
      page: widget.page,
      controller: _controller,
      conflictTitle: 'Window rules differ from saved Settings',
      hero: const SizedBox.shrink(),
      isVisible: (setting) => setting.id != removeWindowRuleId,
      controlBuilder: (setting) => setting.id == setWindowRuleId
          ? _rules(setting)
          : const SizedBox.shrink(),
    ),
  );

  Widget _rules(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
    final rules = _controller.list('window_rules');
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
                rules.isEmpty
                    ? 'Choose an app to float it, size it, send it to a '
                          'workspace or change how it looks.'
                    : 'Rules apply to windows that open after a change.',
                style: text.bodySmall,
              ),
            ],
          ),
          control: FilledButton.icon(
            key: const ValueKey('window-rule-add'),
            onPressed: canChange ? _edit : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ),
        for (final rule in rules)
          Padding(
            key: ValueKey('window-rule-${rule['class']}-${rule['title']}'),
            padding: const .symmetric(horizontal: 20, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                const Icon(Icons.web_asset_rounded),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      Text(_match(rule), style: text.bodyLarge),
                      Text(_facts(rule).join(', '), style: text.bodySmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: canChange ? () => _edit(rule) : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: canChange
                      ? () => _controller.set(removeWindowRuleId, {
                          'class': rule['class'] ?? '',
                          'title': rule['title'] ?? '',
                        })
                      : null,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _Start { normal, maximize, fullscreen }

/// Creates or edits one window rule, with a preview of where the window opens.
class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.controller,
    required this.windows,
    this.initial,
  });
  final FeatureOptionsController controller;
  final List<Map<String, dynamic>> windows;
  final _Rule? initial;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  late final _Rule _r = widget.initial ?? {};
  late final _class = TextEditingController(text: _r['class'] as String?);
  late final _title = TextEditingController(text: _r['title'] as String?);
  late final _workspace = TextEditingController(
    text: _r['workspace'] as String?,
  );
  late bool _float = _r['float'] == true;
  late bool _center = _r['center'] == true;
  late List<int>? _size = (_r['size'] as List?)?.map((v) => v as int).toList();
  late bool _silent = _r['silent'] == true;
  late bool _pin = _r['pin'] == true;
  late _Start _start = _r['fullscreen'] == true
      ? .fullscreen
      : _r['maximize'] == true
      ? .maximize
      : .normal;
  late bool _noFocus = _r['no_initial_focus'] == true;
  late int _opacity = _r['opacity'] as int? ?? 100;
  late bool _noBlur = _r['no_blur'] == true;
  late bool _noShadow = _r['no_shadow'] == true;
  late bool _aspect = _r['keep_aspect_ratio'] == true;
  late String _idleInhibit = _r['idle_inhibit'] as String? ?? '';
  String? _error;

  @override
  void dispose() {
    _class.dispose();
    _title.dispose();
    _workspace.dispose();
    super.dispose();
  }

  bool get _hasMatch =>
      _class.text.trim().isNotEmpty || _title.text.trim().isNotEmpty;

  Future<void> _save() async {
    final workspace = _workspace.text.trim();
    final ok = await widget.controller.set(setWindowRuleId, {
      'class': _class.text.trim(),
      'title': _title.text.trim(),
      'float': _float,
      'center': _float && _center,
      'size': _float ? _size : null,
      'workspace': workspace,
      'silent': workspace.isNotEmpty && _silent,
      'pin': _float && _pin,
      'maximize': _start == .maximize,
      'fullscreen': _start == .fullscreen,
      'no_initial_focus': _noFocus,
      'opacity': _opacity < 100 ? _opacity : null,
      'no_blur': _noBlur,
      'no_shadow': _noShadow,
      'keep_aspect_ratio': _aspect,
      'idle_inhibit': _idleInhibit,
      if (widget.initial case final initial?)
        'previous': {
          'class': initial['class'] ?? '',
          'title': initial['title'] ?? '',
        },
    });
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() => _error = widget.controller.errorMessage);
    }
  }

  Widget _switch(
    String key,
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) => SwitchListTile(
    key: ValueKey('window-rule-$key'),
    contentPadding: .zero,
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle),
    value: value,
    onChanged: (next) => setState(() => onChanged(next)),
  );

  Widget _heading(String label) => Padding(
    padding: const .only(top: 8),
    child: Text(label, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final size = _size;
    return AlertDialog(
      title: Text(
        widget.initial == null ? 'Add a window rule' : 'Edit window rule',
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              _Preview(
                float: _float,
                center: _center,
                size: _float ? size : null,
                start: _start,
                opacity: _opacity,
              ),
              DropdownMenu<String>(
                key: const ValueKey('window-rule-class'),
                controller: _class,
                expandedInsets: .zero,
                enableFilter: true,
                requestFocusOnTap: true,
                label: const Text('App'),
                helperText: 'Pick an open window or type an app class',
                dropdownMenuEntries: [
                  for (final w in widget.windows)
                    DropdownMenuEntry(
                      value: w['class'] as String,
                      label: w['class'] as String,
                      labelWidget: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(w['class'] as String),
                          Text(
                            w['title'] as String? ?? '',
                            style: text.bodySmall,
                            maxLines: 1,
                            overflow: .ellipsis,
                          ),
                        ],
                      ),
                    ),
                ],
                onSelected: (_) => setState(() {}),
              ),
              TextField(
                key: const ValueKey('window-rule-title'),
                controller: _title,
                decoration: const InputDecoration(
                  labelText: 'Only windows whose title contains (optional)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              _heading('Placement'),
              _switch(
                'float',
                'Float',
                _float,
                (v) => _float = v,
                subtitle: 'Open above tiled windows instead of in the layout',
              ),
              if (_float) ...[
                _switch('center', 'Center on the display', _center, (v) {
                  _center = v;
                }),
                _switch('size', 'Set the size', size != null, (v) {
                  _size = v ? [60, 60] : null;
                }),
                if (size != null)
                  for (final (index, label) in ['Width', 'Height'].indexed)
                    Row(
                      children: [
                        SizedBox(width: 64, child: Text(label)),
                        Expanded(
                          child: Slider(
                            key: ValueKey('window-rule-size-$index'),
                            min: 10,
                            max: 100,
                            divisions: 18,
                            value: size[index].toDouble(),
                            label: '${size[index]}%',
                            onChanged: (v) => setState(
                              () => _size = [...size]..[index] = v.round(),
                            ),
                          ),
                        ),
                        SizedBox(width: 48, child: Text('${size[index]}%')),
                      ],
                    ),
                _switch(
                  'pin',
                  'Show on every workspace',
                  _pin,
                  (v) => _pin = v,
                ),
              ],
              SegmentedButton<_Start>(
                key: const ValueKey('window-rule-start'),
                segments: const [
                  ButtonSegment(value: .normal, label: Text('Normal')),
                  ButtonSegment(value: .maximize, label: Text('Maximized')),
                  ButtonSegment(value: .fullscreen, label: Text('Full screen')),
                ],
                selected: {_start},
                showSelectedIcon: false,
                onSelectionChanged: (next) =>
                    setState(() => _start = next.first),
              ),
              TextField(
                key: const ValueKey('window-rule-workspace'),
                controller: _workspace,
                decoration: const InputDecoration(
                  labelText: 'Open on workspace (optional)',
                  helperText: 'A number, name:<name> or special:<name>',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_workspace.text.trim().isNotEmpty)
                _switch(
                  'silent',
                  'Open in the background',
                  _silent,
                  (v) => _silent = v,
                  subtitle: 'Stay on the current workspace',
                ),
              _switch(
                'no-focus',
                'Do not take focus when opening',
                _noFocus,
                (v) => _noFocus = v,
              ),
              _heading('Appearance'),
              Row(
                children: [
                  const SizedBox(width: 64, child: Text('Opacity')),
                  Expanded(
                    child: Slider(
                      key: const ValueKey('window-rule-opacity'),
                      min: 10,
                      max: 100,
                      divisions: 18,
                      value: _opacity.toDouble(),
                      label: '$_opacity%',
                      onChanged: (v) => setState(() => _opacity = v.round()),
                    ),
                  ),
                  SizedBox(width: 48, child: Text('$_opacity%')),
                ],
              ),
              _switch('no-blur', 'No blur', _noBlur, (v) => _noBlur = v),
              _switch(
                'no-shadow',
                'No shadow',
                _noShadow,
                (v) => _noShadow = v,
              ),
              _heading('Behavior'),
              _switch(
                'aspect',
                'Keep the aspect ratio when resizing',
                _aspect,
                (v) => _aspect = v,
              ),
              DropdownMenu<String>(
                key: const ValueKey('window-rule-idle'),
                expandedInsets: .zero,
                label: const Text('Keep the screen awake'),
                initialSelection: _idleInhibit,
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: '', label: 'Never'),
                  for (final MapEntry(:key, :value) in _idle.entries)
                    DropdownMenuEntry(value: key, label: value),
                ],
                onSelected: (next) => setState(() => _idleInhibit = next ?? ''),
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
          key: const ValueKey('window-rule-save'),
          onPressed: _hasMatch && !widget.controller.isBusy ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A display outline with the window where and how the rule opens it.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.float,
    required this.center,
    required this.size,
    required this.start,
    required this.opacity,
  });
  final bool float;
  final bool center;
  final List<int>? size;
  final _Start start;
  final int opacity;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final full = start != .normal;
    final (w, h) = full
        ? (1.0, 1.0)
        : float
        ? ((size?[0] ?? 45) / 100, (size?[1] ?? 45) / 100)
        : (0.5, 1.0);
    // Without centering a floating window opens where the app asks; show it offset.
    final alignment = full || center
        ? Alignment.center
        : float
        ? const Alignment(-0.6, -0.6)
        : Alignment.centerRight;
    final gap = start == .fullscreen ? 0.0 : 6.0;
    return Semantics(
      label: 'Preview of where the window opens',
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: .circular(12),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Padding(
            padding: .all(gap),
            child: Stack(
              children: [
                if (!float && !full)
                  FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Padding(
                      padding: const .only(right: 3),
                      child: _window(colors.surfaceContainerLow, colors, 1),
                    ),
                  ),
                Align(
                  alignment: alignment,
                  child: AnimatedFractionallySizedBox(
                    duration: Durations.medium2,
                    curve: Easing.standard,
                    widthFactor: w,
                    heightFactor: h,
                    child: Padding(
                      padding: .only(left: !float && !full ? 3 : 0),
                      child: _window(
                        colors.primaryContainer,
                        colors,
                        opacity / 100,
                      ),
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

  Widget _window(Color color, ColorScheme colors, double opacity) => Opacity(
    opacity: opacity,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: .circular(8),
        border: Border.all(color: colors.outline),
      ),
      child: const SizedBox.expand(),
    ),
  );
}
