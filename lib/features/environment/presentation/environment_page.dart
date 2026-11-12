import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';

/// Common session variables for apps on Wayland, offered as one-tap fills.
const _suggestions = [
  ('ELECTRON_OZONE_PLATFORM_HINT', 'auto', 'Electron apps use Wayland'),
  ('QT_QPA_PLATFORM', 'wayland;xcb', 'Qt apps prefer Wayland'),
  ('GDK_BACKEND', 'wayland,x11', 'GTK apps prefer Wayland'),
  ('SDL_VIDEODRIVER', 'wayland,x11', 'SDL games prefer Wayland'),
  ('_JAVA_AWT_WM_NONREPARENTING', '1', 'Java apps draw in tiled windows'),
];

/// Session environment variables for apps the desktop starts.
class EnvironmentPage extends StatefulWidget {
  const EnvironmentPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<EnvironmentPage> createState() => _EnvironmentPageState();
}

class _EnvironmentPageState extends State<EnvironmentPage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: 'desktop',
  )..reload();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _edit([Map<String, dynamic>? initial]) => showDialog<void>(
    context: context,
    builder: (_) => _VariableDialog(
      controller: _controller,
      initial: initial,
      used: {for (final v in _controller.list('env')) v['name'] as String},
      reserved: _controller.names('reserved_env').toSet(),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => InputPageFrame(
      catalog: widget.catalog,
      page: widget.page,
      controller: _controller,
      conflictTitle: 'Environment variables differ from saved Settings',
      hero: const SizedBox.shrink(),
      isVisible: (setting) => setting.id != removeEnvironmentVariableId,
      controlBuilder: (setting) => setting.id == setEnvironmentVariableId
          ? _variables(setting)
          : const SizedBox.shrink(),
    ),
  );

  Widget _variables(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
    final variables = _controller.list('env');
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
                'Apps the desktop starts after a change get the new value. '
                'Sign in again for every app, and for a removed variable '
                'to disappear.',
                style: text.bodySmall,
              ),
            ],
          ),
          control: FilledButton.icon(
            key: const ValueKey('environment-add'),
            onPressed: canChange ? _edit : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ),
        for (final v in variables)
          Padding(
            key: ValueKey('environment-${v['name']}'),
            padding: const .symmetric(horizontal: 20, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                const Icon(Icons.data_object_rounded),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 2,
                    children: [
                      SelectableText(
                        v['name'] as String,
                        style: text.bodyLarge?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                      SelectableText(
                        (v['value'] as String).isEmpty
                            ? 'Empty value'
                            : v['value'] as String,
                        style: text.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Edit',
                  onPressed: canChange ? () => _edit(v) : null,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: canChange
                      ? () => _controller.set(removeEnvironmentVariableId, {
                          'name': v['name'],
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

class _VariableDialog extends StatefulWidget {
  const _VariableDialog({
    required this.controller,
    required this.used,
    required this.reserved,
    this.initial,
  });
  final FeatureOptionsController controller;
  final Map<String, dynamic>? initial;
  final Set<String> used;
  final Set<String> reserved;

  @override
  State<_VariableDialog> createState() => _VariableDialogState();
}

class _VariableDialogState extends State<_VariableDialog> {
  late final _name = TextEditingController(
    text: widget.initial?['name'] as String?,
  );
  late final _value = TextEditingController(
    text: widget.initial?['value'] as String?,
  );
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  /// Why the typed name cannot be saved, checked again by the service.
  String? get _nameProblem {
    final name = _name.text.trim();
    if (name.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      return 'Use letters, digits and underscores, not starting with a digit';
    }
    if (widget.reserved.contains(name)) {
      return 'Managed by the session or another Settings page';
    }
    if (name != widget.initial?['name'] && widget.used.contains(name)) {
      return 'Already set; edit it instead';
    }
    return null;
  }

  Future<void> _save() async {
    final ok = await widget.controller.set(setEnvironmentVariableId, {
      'name': _name.text.trim(),
      'value': _value.text,
      'previous': widget.initial?['name'],
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
    final problem = _nameProblem;
    final suggestions = [
      for (final s in _suggestions)
        if (!widget.used.contains(s.$1)) s,
    ];
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add a variable' : 'Edit variable'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              if (widget.initial == null && suggestions.isNotEmpty) ...[
                Text('Suggestions', style: text.titleSmall),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (name, value, label) in suggestions)
                      ActionChip(
                        key: ValueKey('environment-suggest-$name'),
                        label: Text(label),
                        tooltip: '$name=$value',
                        onPressed: () => setState(() {
                          _name.text = name;
                          _value.text = value;
                        }),
                      ),
                  ],
                ),
              ],
              TextField(
                key: const ValueKey('environment-name'),
                controller: _name,
                autofocus: true,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Name',
                  errorText: problem,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              TextField(
                key: const ValueKey('environment-value'),
                controller: _value,
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: const InputDecoration(
                  labelText: 'Value',
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
          key: const ValueKey('environment-save'),
          onPressed:
              _name.text.trim().isEmpty ||
                  problem != null ||
                  widget.controller.isBusy
              ? null
              : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
