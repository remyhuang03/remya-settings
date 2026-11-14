import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/application/feature_options_controller.dart';
import 'input_widgets.dart';
import 'keyboard_map.dart';
import 'shortcut_dialog.dart';
import 'shortcut_model.dart';

/// Every live shortcut on a keyboard map and in a searchable list, plus the user's
/// own shortcuts and the ones they turned off.
class KeyboardShortcutsPage extends StatefulWidget {
  const KeyboardShortcutsPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<KeyboardShortcutsPage> createState() => _KeyboardShortcutsPageState();
}

class _KeyboardShortcutsPageState extends State<KeyboardShortcutsPage> {
  late final _controller = FeatureOptionsController(widget.client)..reload();
  final _dragging = <String, double>{};
  final _search = TextEditingController();
  Set<String> _modifiers = {'SUPER'};
  int? _selected;

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  List<LiveShortcut> get _shortcuts => [
    for (final s in _controller.list('shortcuts')) LiveShortcut(s),
  ];

  ShortcutDraft? _draft(String keys) {
    for (final c in _controller.list('custom')) {
      if (c['keys'] == keys) {
        return (
          keys: keys,
          action: c['action'] as String,
          command: c['command'] as String? ?? '',
          description: c['description'] as String? ?? '',
        );
      }
    }
    return null;
  }

  void _edit({ShortcutDraft? initial, String? keys}) =>
      showShortcutDialog(context, _controller, initial: initial, keys: keys);

  Widget _hero() {
    final text = Theme.of(context).textTheme;
    final selected = _selected;
    final onKey = selected == null
        ? <LiveShortcut>[]
        : KeyboardMap.on(_shortcuts, selected, _modifiers);
    final labels = (_controller.state['key_labels'] as Map? ?? {})
        .cast<String, dynamic>();
    final selectedKeys = selected == null
        ? null
        : [..._modifiers, 'code:$selected'].join(' + ');
    return InputHero(
      caption:
          'Choose modifier keys on the map to see what they do with each key. '
          'Highlighted keys have a shortcut; select one for details.',
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 16,
        children: [
          KeyboardMap(
            shortcuts: _shortcuts,
            labels: labels,
            modifiers: _modifiers,
            selected: _selected,
            onModifier: (m) => setState(
              () => _modifiers = _modifiers.contains(m)
                  ? ({..._modifiers}..remove(m))
                  : {..._modifiers, m},
            ),
            onKey: (code) =>
                setState(() => _selected = _selected == code ? null : code),
          ),
          if (selected != null)
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: .center,
              children: [
                Keycaps(
                  modifiers: _modifiers.toList(),
                  label: labels['$selected'] as String? ?? '$selected',
                ),
                if (onKey.isEmpty)
                  Text('Not used', style: text.bodyMedium)
                else
                  for (final s in onKey) Text(s.title, style: text.bodyMedium),
                if (onKey.isEmpty)
                  FilledButton.tonalIcon(
                    onPressed: _controller.canChange
                        ? () => _edit(keys: selectedKeys)
                        : null,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add a shortcut here'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _custom(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
    final custom = _controller.list('custom');
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
                custom.isEmpty
                    ? 'Run commands or window actions with your own key combinations.'
                    : 'Saved in your Hyprland configuration by Settings.',
                style: text.bodySmall,
              ),
            ],
          ),
          control: FilledButton.icon(
            key: const ValueKey('shortcut-add'),
            onPressed: _controller.canChange ? _edit : null,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add'),
          ),
        ),
        for (final c in custom)
          _ShortcutRow(
            title: (c['description'] as String? ?? '').isNotEmpty
                ? c['description'] as String
                : shortcutActions[c['action']] ?? '${c['action']}',
            subtitle: c['action'] == 'command'
                ? c['command'] as String
                : shortcutActions[c['action']],
            modifiers: (c['modifiers'] as List).cast(),
            label: c['label'] as String? ?? '',
            actions: [
              IconButton(
                tooltip: 'Edit',
                onPressed: _controller.canChange
                    ? () => _edit(initial: _draft(c['keys'] as String))
                    : null,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: _controller.canChange
                    ? () =>
                          _controller.set(removeShortcutId, {'keys': c['keys']})
                    : null,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
      ],
    );
  }

  Widget _disabled(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
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
                'Restoring one reloads the Hyprland configuration.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
        for (final d in _controller.list('disabled'))
          _ShortcutRow(
            title: 'Turned off',
            modifiers: (d['modifiers'] as List).cast(),
            label: d['label'] as String? ?? '',
            actions: [
              TextButton(
                onPressed: _controller.canChange
                    ? () => _controller.set(disableShortcutId, {
                        'keys': d['keys'],
                        'disabled': false,
                      })
                    : null,
                child: const Text('Restore'),
              ),
            ],
          ),
      ],
    );
  }

  Widget _list(SettingSpec setting) {
    final query = _search.text.trim().toLowerCase();
    final matches = [
      for (final s in _shortcuts)
        if (query.isEmpty ||
            [
              s.title,
              s.category,
              s.keys,
              s.label,
              ...s.actions,
            ].join(' ').toLowerCase().contains(query))
          s,
    ];
    final categories = <String, List<LiveShortcut>>{};
    for (final s in matches) {
      (categories[s.category] ??= []).add(s);
    }
    final text = Theme.of(context).textTheme;
    return Column(
      key: ValueKey(setting.id),
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .fromLTRB(20, 18, 20, 8),
          child: SearchBar(
            key: const ValueKey('shortcut-search'),
            controller: _search,
            hintText: 'Search ${_shortcuts.length} shortcuts',
            leading: const Icon(Icons.search_rounded),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (_) => setState(() {}),
          ),
        ),
        if (matches.isEmpty)
          Padding(
            padding: const .all(20),
            child: Text('No shortcut matches.', style: text.bodyMedium),
          ),
        for (final MapEntry(key: category, value: items)
            in categories.entries) ...[
          Padding(
            padding: const .fromLTRB(20, 16, 20, 4),
            child: Text(category, style: text.titleSmall),
          ),
          for (final s in items)
            _ShortcutRow(
              title: s.title,
              subtitle: [
                if (s.description.isNotEmpty) s.actions.join(', '),
                if (s.submap.isNotEmpty) 'Only in the ${s.submap} mode',
              ].join('\n'),
              modifiers: s.modifiers,
              label: s.label,
              actions: [
                if (s.custom)
                  IconButton(
                    tooltip: 'Edit',
                    onPressed: _controller.canChange && _draft(s.keys) != null
                        ? () => _edit(initial: _draft(s.keys))
                        : null,
                    icon: const Icon(Icons.edit_outlined),
                  )
                else if (s.submap.isEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    enabled: _controller.canChange,
                    onSelected: (choice) => choice == 'off'
                        ? _controller.set(disableShortcutId, {
                            'keys': s.keys,
                            'disabled': true,
                          })
                        : _edit(keys: s.keys),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'replace',
                        child: Text('Replace with my own'),
                      ),
                      PopupMenuItem(value: 'off', child: Text('Turn off')),
                    ],
                  ),
              ],
            ),
        ],
        const SizedBox(height: 12),
      ],
    );
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
        hero: _hero(),
        isVisible: (setting) => switch (setting.id) {
          removeShortcutId || recordShortcutId => false,
          disableShortcutId => _controller.list('disabled').isNotEmpty,
          _ => true,
        },
        controlBuilder: (setting) => switch (setting.id) {
          addShortcutId => _custom(setting),
          disableShortcutId => _disabled(setting),
          'keyboard-shortcuts.list' => _list(setting),
          _ => rows.build(setting),
        },
      );
    },
  );
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.title,
    required this.modifiers,
    required this.label,
    required this.actions,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<String> modifiers;
  final String label;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const .symmetric(horizontal: 20, vertical: 8),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text(title, style: text.bodyLarge),
                if (subtitle case final subtitle? when subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: .ellipsis,
                  ),
              ],
            ),
          ),
          Flexible(
            child: Align(
              alignment: .centerRight,
              child: Keycaps(modifiers: modifiers, label: label),
            ),
          ),
          ...actions,
          if (actions.isEmpty) const SizedBox(width: 48),
        ],
      ),
    );
  }
}
