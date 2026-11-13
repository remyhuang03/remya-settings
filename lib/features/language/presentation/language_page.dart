import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';

/// XKB `grp:` options offered for switching layouts, in the catalog's option order.
const switchOptions = <String?>[
  null,
  'grp:win_space_toggle',
  'grp:alt_shift_toggle',
  'grp:ctrl_shift_toggle',
  'grp:alt_space_toggle',
  'grp:ctrl_space_toggle',
  'grp:caps_toggle',
  'grp:shifts_toggle',
];

/// Display language and regional format (`language`) and keyboard layouts (`input`).
class LanguagePage extends StatefulWidget {
  const LanguagePage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
    this.environment,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  /// This session's locale environment; defaults to the process environment.
  final Map<String, String>? environment;

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  late final _language = FeatureOptionsController(
    widget.client,
    feature: 'language',
  )..reload();
  late final _input = FeatureOptionsController(widget.client)..reload();
  List<({String id, String label})> _locales = [];
  List<Map<String, dynamic>> _layouts = [];
  Map<String, dynamic>? _preview;
  String? _previewLocale;
  String? _listError;

  @override
  void initState() {
    super.initState();
    _language.addListener(_updatePreview);
    unawaited(_loadLists());
  }

  @override
  void dispose() {
    _language.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadLists() async {
    try {
      final locales = await widget.client.call('Get', ['locales']);
      final layouts = await widget.client.call('Get', ['keyboard-layouts']);
      if (!mounted) return;
      setState(() {
        _locales = [
          for (final option in (locales['options'] as List).cast<Map>())
            (id: option['id'] as String, label: option['label'] as String),
        ];
        _layouts = (layouts['layouts'] as List)
            .cast<Map>()
            .map((m) => m.cast<String, dynamic>())
            .toList();
      });
    } catch (error) {
      if (mounted) setState(() => _listError = '$error');
    }
  }

  String? get _displayLanguage =>
      _language.option(displayLanguageId) as String?;

  /// The locale the format categories use, for the preview.
  String? get _formatLocale {
    final formats = (_language.state['formats'] as Map?)
        ?.cast<String, String>();
    final time = formats?['LC_TIME'];
    return time == null || time.isEmpty ? _displayLanguage : time;
  }

  Future<void> _updatePreview() async {
    final locale = _formatLocale;
    if (locale == null || locale == _previewLocale) return;
    _previewLocale = locale;
    try {
      final preview = await widget.client.call('Get', [
        'format-preview:$locale',
      ]);
      if (mounted && _previewLocale == locale) {
        setState(() => _preview = preview);
      }
    } catch (_) {
      if (mounted) setState(() => _preview = null);
    }
  }

  String _label(String? id) {
    if (id == null) return 'Unknown';
    for (final locale in _locales) {
      if (locale.id == id) return locale.label;
    }
    return id;
  }

  /// Programs in this session keep the locale they started with.
  bool get _signInPending {
    final env = widget.environment ?? Platform.environment;
    final saved = _displayLanguage;
    final formats = (_language.state['formats'] as Map?)
        ?.cast<String, String>();
    if (saved == null || formats == null) return false;
    String norm(String? v) => (v ?? '').replaceAll('-', '').toLowerCase();
    final session = env['LANG'];
    if (norm(session) != norm(saved)) return true;
    return formats.entries.any((e) {
      final wanted = e.value.isEmpty ? saved : e.value;
      return norm(env[e.key] ?? session) != norm(wanted);
    });
  }

  Future<void> _chooseLocale(SettingSpec setting) async {
    final format = setting.id == regionalFormatId;
    final current = format
        ? _language.option(regionalFormatId) as String?
        : _displayLanguage;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _Picker(
        title: format
            ? 'Choose a regional format'
            : 'Choose a display language',
        searchLabel: 'Search languages and regions',
        entries: [
          if (format) (id: '', label: 'Same as display language', detail: ''),
          for (final locale in _locales)
            (id: locale.id, label: locale.label, detail: locale.id),
        ],
        selected: current,
      ),
    );
    if (value != null && value != current) {
      await _language.set(setting.id, value);
    }
  }

  Widget _localeRow(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
    final format = setting.id == regionalFormatId;
    final value = _language.option(setting.id);
    final shown = !format
        ? _label(value as String?)
        : switch (value) {
            '' => 'Same as display language',
            null => 'Custom for each category',
            final String id => _label(id),
            _ => '$value',
          };
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SettingRow(
          id: setting.id,
          label: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Text(setting.title, style: text.bodyLarge),
              Text(
                format
                    ? 'Dates, times, numbers, currency, paper size and units'
                    : 'Only locales generated on this computer are listed. '
                          'Generating others needs administrator access to '
                          '/etc/locale.gen and is not done here.',
                style: text.bodySmall,
              ),
              if (_signInPending)
                Row(
                  spacing: 8,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                    Flexible(
                      child: Text(
                        'Sign out and back in to apply',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          control: FilledButton.tonalIcon(
            key: ValueKey('${setting.id}-choose'),
            onPressed: _language.canChange && _locales.isNotEmpty
                ? () => _chooseLocale(setting)
                : null,
            icon: const Icon(Icons.expand_more_rounded),
            label: Text(shown, overflow: .ellipsis),
          ),
        ),
        if (format && _preview != null)
          Padding(
            padding: const .fromLTRB(20, 0, 20, 18),
            child: _FormatPreview(preview: _preview!),
          ),
      ],
    );
  }

  List<Map<String, dynamic>> get _current =>
      ((_input.option(keyboardLayoutsId) as List?) ?? [])
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

  String _layoutLabel(Map<String, dynamic> entry) {
    for (final layout in _layouts) {
      if (layout['id'] != entry['layout']) continue;
      if (entry['variant'] == '') return layout['label'] as String;
      for (final variant in (layout['variants'] as List).cast<Map>()) {
        if (variant['id'] == entry['variant']) {
          return variant['label'] as String;
        }
      }
    }
    final variant = entry['variant'] as String;
    return variant.isEmpty
        ? '${entry['layout']}'
        : '${entry['layout']} ($variant)';
  }

  Future<void> _setLayouts(List<Map<String, dynamic>> next) =>
      _input.set(keyboardLayoutsId, next);

  Future<void> _addLayout() async {
    final current = _current;
    String key(Object? layout, Object? variant) => '$layout($variant)';
    final taken = {for (final e in current) key(e['layout'], e['variant'])};
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _Picker(
        title: 'Add a keyboard layout',
        searchLabel: 'Search keyboard layouts',
        entries: [
          for (final layout in _layouts) ...[
            (
              id: key(layout['id'], ''),
              label: layout['label'] as String,
              detail: layout['id'] as String,
            ),
            for (final variant in (layout['variants'] as List).cast<Map>())
              (
                id: key(layout['id'], variant['id']),
                label: variant['label'] as String,
                detail: '${layout['id']} (${variant['id']})',
              ),
          ],
        ].where((e) => !taken.contains(e.id)).toList(),
        selected: null,
      ),
    );
    if (value == null) return;
    final open = value.indexOf('(');
    await _setLayouts([
      ...current,
      {
        'layout': value.substring(0, open),
        'variant': value.substring(open + 1, value.length - 1),
      },
    ]);
  }

  Widget _layoutsRow(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
    final current = _current;
    final enabled = _input.canChange && _layouts.isNotEmpty;
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .stretch,
        spacing: 4,
        children: [
          Text(setting.title, style: text.bodyLarge),
          Text(
            'The first layout is the default. Changes apply immediately.',
            style: text.bodySmall,
          ),
          for (var i = 0; i < current.length; i++)
            ListTile(
              key: ValueKey(
                'layout-${current[i]['layout']}-${current[i]['variant']}',
              ),
              contentPadding: .zero,
              leading: const Icon(Icons.keyboard_outlined),
              title: Text(_layoutLabel(current[i])),
              subtitle: Text(i == 0 ? 'Default' : 'Layout ${i + 1}'),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    onPressed: enabled && i > 0
                        ? () => _setLayouts([
                            ...current.sublist(0, i - 1),
                            current[i],
                            current[i - 1],
                            ...current.sublist(i + 1),
                          ])
                        : null,
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: enabled && current.length > 1
                        ? () => _setLayouts([...current]..removeAt(i))
                        : null,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
          Align(
            alignment: .centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('add-keyboard-layout'),
              // XKB keymaps hold at most four layouts.
              onPressed: enabled && current.length < 4 ? _addLayout : null,
              icon: const Icon(Icons.add_rounded),
              label: Text(setting.value as String),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchRow(SettingSpec setting) {
    final text = Theme.of(context).textTheme;
    final options = (_input.option(keyboardOptionsId) as String? ?? '')
        .split(',')
        .where((o) => o.isNotEmpty)
        .toList();
    final group = options.where((o) => o.startsWith('grp:')).toList();
    final index = group.isEmpty
        ? 0
        : group.length == 1
        ? switchOptions.indexOf(group.single)
        : -1;
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(setting.title, style: text.bodyLarge),
          Text(
            index < 0 ? 'Custom: ${group.join(', ')}' : setting.reason,
            style: text.bodySmall,
          ),
        ],
      ),
      control: DropdownMenu<int>(
        key: ValueKey('${setting.id}-$index'),
        width: 260,
        enabled: _input.canChange,
        initialSelection: index < 0 ? null : index,
        hintText: 'Custom',
        dropdownMenuEntries: [
          for (var i = 0; i < switchOptions.length; i++)
            DropdownMenuEntry(value: i, label: setting.options[i]),
        ],
        onSelected: (next) {
          if (next == null || next == index) return;
          _input.set(
            keyboardOptionsId,
            [
              ...options.where((o) => !o.startsWith('grp:')),
              ?switchOptions[next],
            ].join(','),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_language, _input]),
    builder: (context, _) => InputPageFrame(
      catalog: widget.catalog,
      page: widget.page,
      controller: _language,
      conflictTitle: 'Language settings differ from saved Settings',
      hero: Column(
        crossAxisAlignment: .stretch,
        children: [
          if (_listError case final error?)
            SettingsErrorCard(message: error, onRetry: _loadLists),
          if (_input.errorMessage case final error?)
            SettingsErrorCard(message: error, onRetry: _input.reload),
          if (_input.writeBlocked case final reason?)
            SettingsErrorCard(message: reason, onRetry: _input.reload),
          if (_input.hasConflict)
            InputConflictCard(
              controls: widget.catalog.pages.expand((p) => p.controls),
              controller: _input,
            ),
        ],
      ),
      isVisible: (setting) =>
          setting.id != keyboardOptionsId || _current.length > 1,
      controlBuilder: (setting) => switch (setting.id) {
        displayLanguageId || regionalFormatId => _localeRow(setting),
        keyboardLayoutsId => _layoutsRow(setting),
        keyboardOptionsId => _switchRow(setting),
        _ => SettingControlTile(setting),
      },
    ),
  );
}

/// Sample values in the chosen regional format, as labeled fields.
class _FormatPreview extends StatelessWidget {
  const _FormatPreview({required this.preview});
  final Map<String, dynamic> preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    const fields = {
      'date': 'Date',
      'time': 'Time',
      'weekday': 'Day',
      'number': 'Number',
      'currency': 'Currency',
      'measurement': 'Units',
      'paper': 'Paper',
    };
    return DecoratedBox(
      key: const ValueKey('format-preview'),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: .circular(16),
      ),
      child: Padding(
        padding: const .all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            for (final MapEntry(:key, :value) in fields.entries)
              Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    value,
                    style: text.labelMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text('${preview[key] ?? ''}', style: text.bodyLarge),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// A searchable list dialog returning the chosen entry's ID.
class _Picker extends StatefulWidget {
  const _Picker({
    required this.title,
    required this.searchLabel,
    required this.entries,
    required this.selected,
  });
  final String title;
  final String searchLabel;
  final List<({String id, String label, String detail})> entries;
  final String? selected;

  @override
  State<_Picker> createState() => _PickerState();
}

class _PickerState extends State<_Picker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final matches = widget.entries
        .where(
          (e) =>
              e.label.toLowerCase().contains(query) ||
              e.detail.toLowerCase().contains(query),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('picker-search'),
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.searchLabel,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (matches.length == 1) {
                  Navigator.pop(context, matches.single.id);
                }
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('Nothing found'))
                  : ListView.builder(
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final entry = matches[index];
                        final selected = entry.id == widget.selected;
                        return ListTile(
                          key: ValueKey('picker-${entry.id}'),
                          selected: selected,
                          title: Text(entry.label, overflow: .ellipsis),
                          subtitle: entry.detail.isEmpty
                              ? null
                              : Text(entry.detail),
                          trailing: selected
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, entry.id),
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
}
