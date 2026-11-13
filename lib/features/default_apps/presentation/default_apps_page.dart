import 'dart:async';

import '../../applications/presentation/application_icon.dart';

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../../settings/presentation/settings_list.dart';
import '../application/default_apps_controller.dart';

class DefaultAppsPage extends StatefulWidget {
  const DefaultAppsPage({super.key, required this.controller});
  final DefaultAppsController controller;
  @override
  State<DefaultAppsPage> createState() => _DefaultAppsPageState();
}

class _DefaultAppsPageState extends State<DefaultAppsPage> {
  String _query = '';
  Timer? _debounce;
  List<Map>? _types;
  DefaultApplication? _application;
  String? _searchError;
  bool _searching = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _queryChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _query = value.trim();
      _types = null;
      _application = null;
      _request++;
      _searching = false;
      _searchError = null;
    });
    if (_query.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 250), _search);
    }
  }

  Future<void> _search() async {
    if (_query.isEmpty) return;
    final request = ++_request;
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final result = await widget.controller.searchTypes(_query);
      if (mounted && request == _request) {
        setState(() {
          _types = (result['types'] as List).cast<Map>();
          _application = null;
        });
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _searchError = '$error');
      }
    } finally {
      if (mounted && request == _request) setState(() => _searching = false);
    }
  }

  Future<void> _choose(
    String setting,
    List<String> types, {
    bool shortcut = false,
    String? applicationId,
  }) async {
    final controller = widget.controller;
    final candidates = controller.apps
        .where(
          (a) =>
              (shortcut
                  ? types.any(a.types.contains)
                  : types.every(a.types.contains)) &&
              (applicationId == null || a.id == applicationId) &&
              (setting != 'defaults.ccac113f' || types.every(a.types.contains)),
        )
        .toList();
    final application = await showDialog<DefaultApplication>(
      context: context,
      builder: (_) => _ApplicationPicker(apps: candidates, types: types),
    );
    if (application == null || !mounted || !controller.canChange) return;
    await controller.set(setting, application.id, shortcut ? [] : types);
  }

  Future<void> _associations(
    String title,
    List<String> types,
    String setting,
  ) => showDialog<void>(
    context: context,
    builder: (_) => _AssociationsDialog(
      title: title,
      types: types,
      controller: widget.controller,
      choose: (type) => _choose(defaultAppsTypeSettingId, [type]),
      setAll: () => _choose(setting, types, shortcut: true),
    ),
  );

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset all default apps?'),
        content: const Text(
          'This clears your shared default apps for files and links, along with overrides for the current desktop. '
          'Your desktop will choose from the remaining associations.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && widget.controller.canChange) {
      await widget.controller.resetAll();
    }
  }

  Widget _typeRow(String type) => SettingRow(
    key: ValueKey('default-type-$type'),
    id: type,
    label: _SelectedApplications(
      title: type,
      types: [type],
      controller: widget.controller,
    ),
    control: FilledButton.icon(
      onPressed: widget.controller.canChange
          ? () => _choose(defaultAppsTypeSettingId, [type])
          : null,
      icon: const Icon(Icons.edit_outlined),
      label: const Text('Change'),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final app = _application;
      final matches = controller.apps
          .where(
            (a) => '${a.name} ${a.id}'.toLowerCase().contains(
              _query.toLowerCase(),
            ),
          )
          .toList();
      final typeList = app?.types;
      final shown = typeList?.length ?? matches.length;
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          const Text(
            'Changes apply immediately to XDG file and link associations. Applications with custom openers may use their own preferences.',
          ),
          const SizedBox(height: 16),
          if (controller.hasConflict)
            SettingsSurface(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  const Icon(Icons.warning_amber_rounded),
                  const Text('Default apps differ from saved Settings'),
                  const SizedBox(height: 8),
                  Text(controller.conflictSummary),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: controller.isBusy
                            ? null
                            : controller.useSystemConfiguration,
                        child: const Text('Use system configuration'),
                      ),
                      TextButton(
                        onPressed: controller.isBusy
                            ? null
                            : controller.applySavedConfiguration,
                        child: const Text('Apply saved Settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (controller.errorMessage case final error?)
            SettingsErrorCard(
              message: error,
              onRetry: controller.isBusy ? null : controller.reload,
            ),
          if (controller.isBusy || _searching) const LinearProgressIndicator(),
          SettingsSurface(
            padding: .zero,
            child: Column(
              children: [
                for (final group in controller.groups)
                  SettingRow(
                    id: group['id'] as String,
                    label: InkWell(
                      onTap: () => _associations(
                        group['title'] as String,
                        (group['types'] as List).cast<String>(),
                        group['id'] as String,
                      ),
                      child: _SelectedApplications(
                        title: group['title'] as String,
                        types: (group['types'] as List).cast<String>(),
                        controller: controller,
                      ),
                    ),
                    control: FilledButton.icon(
                      key: ValueKey("choose-${group['id']}"),
                      onPressed: controller.canChange
                          ? () => _associations(
                              group['title'] as String,
                              (group['types'] as List).cast<String>(),
                              group['id'] as String,
                            )
                          : null,
                      icon: const Icon(Icons.tune_rounded),
                      label: const Text('Manage'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (_searchError case final error?) Text(error),
          SettingsList(
            title: app == null
                ? 'Applications (${matches.length})'
                : '${app.name}: file and link types (${app.types.length})',
            actions: [
              SizedBox(
                width: 260,
                child: TextField(
                  key: const ValueKey('default-search'),
                  decoration: const InputDecoration(
                    labelText: 'Search applications or file types',
                    hintText: 'App name, .pdf, image/png or https',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: _queryChanged,
                  onSubmitted: (_) {
                    _debounce?.cancel();
                    _search();
                  },
                ),
              ),
              if (app != null) ...[
                IconButton(
                  tooltip: 'Back to applications',
                  onPressed: () => setState(() => _application = null),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                FilledButton(
                  onPressed:
                      controller.canChange &&
                          app.types.isNotEmpty &&
                          app.types.length <= 256
                      ? () => _choose(
                          defaultAppsSearchSettingId,
                          app.types,
                          applicationId: app.id,
                        )
                      : null,
                  child: const Text('Set defaults'),
                ),
              ],
            ],
            empty: const Text('No matches found'),
            itemCount: shown,
            findChildIndexCallback: (key) {
              final index = typeList != null
                  ? typeList.indexWhere(
                      (type) => ValueKey('default-type-$type') == key,
                    )
                  : matches.indexWhere((app) => ValueKey(app.id) == key);
              return index < 0 ? null : index;
            },
            itemBuilder: (context, index) {
              if (typeList != null) return _typeRow(typeList[index]);
              final match = matches[index];
              return ListTile(
                key: ValueKey(match.id),
                leading: ApplicationIcon(icon: match.icon),
                title: Text(match.name),
                subtitle: Text(
                  '${match.id}\n${match.types.length} supported types',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => setState(() {
                  _debounce?.cancel();
                  _request++;
                  _searching = false;
                  _application = match;
                }),
              );
            },
          ),
          if (app == null && _query.isNotEmpty && _types != null) ...[
            const SizedBox(height: 24),
            SettingsList(
              title: 'File and link types (${_types!.length})',
              empty: const Text('No matching file types'),
              itemCount: _types!.length,
              findChildIndexCallback: (key) {
                final index = _types!.indexWhere(
                  (type) => ValueKey('default-type-${type['type']}') == key,
                );
                return index < 0 ? null : index;
              },
              itemBuilder: (context, index) =>
                  _typeRow(_types![index]['type'] as String),
            ),
          ],
          const SizedBox(height: 24),
          SettingsSurface(
            padding: .zero,
            child: SettingRow(
              id: defaultAppsResetSettingId,
              label: const Text('Reset all default apps'),
              control: OutlinedButton(
                onPressed: controller.canChange ? _confirmReset : null,
                child: const Text('Reset'),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SelectedApplications extends StatelessWidget {
  const _SelectedApplications({
    required this.title,
    required this.types,
    required this.controller,
  });
  final String title;
  final List<String> types;
  final DefaultAppsController controller;
  @override
  Widget build(BuildContext context) {
    final ids = types
        .map((t) => controller.system[t] as String?)
        .toSet()
        .toList();
    final assigned = ids.where((id) => id?.isNotEmpty == true).toList();
    final icons = assigned.isEmpty ? <String?>[null] : assigned;
    return Column(
      crossAxisAlignment: .start,
      children: [
        Row(
          mainAxisSize: .min,
          children: [
            Icon(switch (title) {
              'Web browser' => Icons.language_rounded,
              'Mail' => Icons.mail_outline_rounded,
              'Photos' => Icons.photo_library_outlined,
              'Video' => Icons.video_library_outlined,
              'Audio' => Icons.music_note_outlined,
              'Text editor' => Icons.edit_note_rounded,
              'PDF' => Icons.picture_as_pdf_outlined,
              'File manager' => Icons.folder_outlined,
              _ => Icons.insert_drive_file_outlined,
            }, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: .min,
          children: [
            if (icons.length == 1)
              ApplicationIcon(icon: controller.application(icons.single)?.icon)
            else
              SizedBox(
                width: 44 + 20 * (icons.take(3).length - 1),
                height: 44,
                child: Stack(
                  key: ValueKey('selected-app-icons-$title'),
                  children: [
                    for (var i = 0; i < icons.take(3).length; i++)
                      Positioned(
                        left: i * 20.0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerLowest,
                            shape: .circle,
                            border: Border.all(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLowest,
                              width: 2,
                            ),
                          ),
                          child: ApplicationIcon(
                            icon: controller.application(icons[i])?.icon,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                ids.length == 1
                    ? controller.name(ids.single)
                    : ids.every((id) => id?.isNotEmpty == true)
                    ? '${ids.length} applications'
                    : 'Mixed defaults',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
            if (ids.length > 1) const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ],
    );
  }
}

class _AssociationsDialog extends StatefulWidget {
  const _AssociationsDialog({
    required this.title,
    required this.types,
    required this.controller,
    required this.choose,
    required this.setAll,
  });
  final String title;
  final List<String> types;
  final DefaultAppsController controller;
  final Future<void> Function(String) choose;
  final Future<void> Function() setAll;
  @override
  State<_AssociationsDialog> createState() => _AssociationsDialogState();
}

class _AssociationsDialogState extends State<_AssociationsDialog> {
  String _query = '';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final extensions = controller.value['extensions'] as Map? ?? {};
      final entries =
          [
                for (final type in widget.types)
                  for (final extension
                      in ((extensions[type] as List?)?.cast<String>() ??
                          [type]))
                    (type: type, extension: extension),
              ]
              .where(
                (entry) => '${entry.extension} ${entry.type}'
                    .toLowerCase()
                    .contains(_query.toLowerCase()),
              )
              .toList();
      return AlertDialog(
        title: Text(widget.title),
        scrollable: true,
        content: SizedBox(
          width: 560,
          height: 440,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              const Text(
                'Choose an application for each file type. Extensions sharing the same MIME type change together.',
              ),
              const SizedBox(height: 12),
              if (controller.errorMessage case final error?)
                Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (controller.isBusy) const LinearProgressIndicator(),
              Expanded(
                child: SettingsList(
                  title: 'File and link types (${entries.length})',
                  actions: [
                    SizedBox(
                      width: 232,
                      child: TextField(
                        key: const ValueKey('association-search'),
                        decoration: const InputDecoration(
                          labelText: 'Search extensions',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    FilledButton(
                      onPressed: controller.canChange ? widget.setAll : null,
                      child: const Text('Set all'),
                    ),
                  ],
                  empty: const Text('No matching file types'),
                  itemCount: entries.length,
                  findChildIndexCallback: (key) {
                    final index = entries.indexWhere(
                      (e) =>
                          ValueKey(
                            'association-item-${e.extension}-${e.type}',
                          ) ==
                          key,
                    );
                    return index < 0 ? null : index;
                  },
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final id = controller.system[entry.type] as String?;
                    return SettingRow(
                      key: ValueKey(
                        'association-item-${entry.extension}-${entry.type}',
                      ),
                      id: 'association-${entry.extension}-${entry.type}',
                      label: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(entry.extension),
                          Text(
                            entry.type,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisSize: .min,
                            children: [
                              ApplicationIcon(
                                icon: controller.application(id)?.icon,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Flexible(child: Text(controller.name(id))),
                            ],
                          ),
                        ],
                      ),
                      control: FilledButton.icon(
                        onPressed: controller.canChange
                            ? () => widget.choose(entry.type)
                            : null,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Change'),
                      ),
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
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _ApplicationPicker extends StatefulWidget {
  const _ApplicationPicker({required this.apps, required this.types});
  final List<DefaultApplication> apps;
  final List<String> types;
  @override
  State<_ApplicationPicker> createState() => _ApplicationPickerState();
}

class _ApplicationPickerState extends State<_ApplicationPicker> {
  String _query = '';
  DefaultApplication? _selected;
  @override
  Widget build(BuildContext context) {
    final matches = widget.apps
        .where(
          (a) =>
              '${a.name} ${a.id}'.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    final selected = _selected;
    return AlertDialog(
      title: const Text('Choose a default application'),
      scrollable: true,
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Expanded(
              child: SettingsList(
                title: 'Applications (${matches.length})',
                actions: [
                  SizedBox(
                    width: 232,
                    child: TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Search applications',
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
                empty: const Text(
                  'No installed application declares support for these types.',
                ),
                itemCount: matches.length,
                findChildIndexCallback: (key) {
                  final index = matches.indexWhere(
                    (app) => ValueKey(app.id) == key,
                  );
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) {
                  final app = matches[index];
                  return ListTile(
                    key: ValueKey(app.id),
                    leading: ApplicationIcon(icon: app.icon),
                    trailing: selected?.id == app.id
                        ? const Icon(Icons.check_circle_rounded)
                        : null,
                    title: Text(app.name),
                    subtitle: Text(app.id),
                    selected: selected?.id == app.id,
                    onTap: () => setState(() => _selected = app),
                  );
                },
              ),
            ),
            if (selected != null) ...[
              const Divider(),
              const Text('Types that will change:'),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 100),
                child: SingleChildScrollView(
                  child: Text(
                    widget.types.where(selected.types.contains).join('\n'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: selected == null
              ? null
              : () => Navigator.pop(context, selected),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: const Text('Set default'),
        ),
      ],
    );
  }
}
