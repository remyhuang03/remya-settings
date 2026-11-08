import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import '../../settings/presentation/settings_widgets.dart';

/// Notifications, Automatic Do Not Disturb and Priority notifications. The
/// desktop notification service (Remy'a Bar) applies every change live.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({
    super.key,
    required this.client,
    required this.catalog,
    required this.page,
    required this.onPage,
  });

  static const pageIds = {
    'notifications',
    'quiet-schedule',
    'priority-notifications',
  };

  final SettingsClient client;
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final ValueChanged<SettingsPageSpec> onPage;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const _links = {
    'notifications.automatic-dnd': 'quiet-schedule',
    'notifications.priority': 'priority-notifications',
  };
  static const _repeats = {
    'every-day': 'Every day',
    'weekdays': 'Weekdays',
    'weekends': 'Weekends',
  };

  NotificationPreferences? _preferences;
  bool _busy = false;
  String? _error;
  late final StreamSubscription<SettingsChange> _changes;

  @override
  void initState() {
    super.initState();
    _changes = widget.client.changes
        .where((change) => notificationSettingIds.contains(change.topic))
        .listen((_) => _load(), onError: (Object _) {});
    _load();
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  // Errors keep the last valid preferences on screen.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      final next = await widget.client.readNotificationPreferences();
      if (mounted) {
        setState(() {
          _preferences = next;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {});

  void _set(String id, Object value) =>
      _run(() => widget.client.setNotificationPreference(id, value));

  Widget _label(SettingSpec setting, {String? detail}) => Column(
    crossAxisAlignment: .start,
    spacing: 6,
    children: [
      Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
      Text(
        detail ?? setting.reason,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );

  Widget _toggle(SettingSpec setting, bool value) => SettingRow(
    id: setting.id,
    label: _label(setting),
    control: Semantics(
      label: setting.title,
      child: Switch(
        value: value,
        onChanged: _busy ? null : (next) => _set(setting.id, next),
      ),
    ),
  );

  Widget _choice<T extends Object>(
    SettingSpec setting,
    T selected,
    Map<T, String> choices, {
    double width = 200,
  }) => SettingRow(
    id: setting.id,
    label: _label(setting),
    control: DropdownMenu<T>(
      key: ValueKey('${setting.id}-$selected'),
      width: width,
      enabled: !_busy,
      initialSelection: selected,
      dropdownMenuEntries: [
        for (final entry in {
          ...choices,
          if (!choices.containsKey(selected)) selected: '$selected',
        }.entries)
          DropdownMenuEntry(value: entry.key, label: entry.value),
      ],
      onSelected: (value) {
        if (value != null && value != selected) _set(setting.id, value);
      },
    ),
  );

  Widget _time(SettingSpec setting, String value) {
    final [hours, minutes] = value.split(':').map(int.parse).toList();
    return SettingRow(
      id: setting.id,
      label: _label(setting),
      control: OutlinedButton.icon(
        icon: const Icon(Icons.schedule_rounded),
        label: Text(value),
        onPressed: _busy
            ? null
            : () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: hours, minute: minutes),
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  ),
                );
                if (picked == null) return;
                String two(int value) => '$value'.padLeft(2, '0');
                _set(setting.id, '${two(picked.hour)}:${two(picked.minute)}');
              },
      ),
    );
  }

  Widget _apps(SettingSpec setting, List<PriorityApp> apps) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        SettingRow(
          id: setting.id,
          label: _label(setting),
          control: FilledButton.tonalIcon(
            onPressed: _busy ? null : _addApp,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add app'),
          ),
        ),
        if (apps.isEmpty)
          SettingRow(
            id: '${setting.id}-empty',
            label: Text('No priority apps', style: text.bodyMedium),
          ),
        for (final app in apps)
          SettingRow(
            id: '${setting.id}-${app.id}',
            label: Column(
              crossAxisAlignment: .start,
              children: [
                Text(app.name, style: text.bodyLarge),
                Text(app.id, style: text.bodySmall),
              ],
            ),
            control: IconButton(
              tooltip: 'Remove',
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => widget.client.setPriorityApp(app, priority: false),
                    ),
              icon: const Icon(Icons.remove_circle_outline_rounded),
            ),
          ),
      ],
    );
  }

  Future<void> _addApp() async {
    final app = await showDialog<PriorityApp>(
      context: context,
      builder: (context) => _AppPicker(
        client: widget.client,
        exclude: {for (final app in _preferences!.priorityApps) app.id},
      ),
    );
    if (app != null) {
      await _run(() => widget.client.setPriorityApp(app, priority: true));
    }
  }

  Widget _control(SettingSpec setting) {
    final preferences = _preferences;
    if (_links[setting.id] case final page?) {
      return SettingControlTile(
        setting,
        onOpenPage: () => widget.onPage(widget.catalog.page(page)),
      );
    }
    if (preferences == null) return SettingControlTile(setting);
    return switch (setting.id) {
      notificationDndSettingId => _toggle(setting, preferences.doNotDisturb),
      notificationSoundsSettingId => _toggle(setting, preferences.sounds),
      quietScheduleSettingId => _toggle(setting, preferences.schedule),
      quietFullscreenSettingId => _toggle(setting, preferences.fullscreen),
      priorityCallsSettingId => _toggle(setting, preferences.priorityCalls),
      notificationDurationSettingId => _choice(
        setting,
        preferences.popupDuration,
        {
          for (final seconds in notificationDurations)
            seconds: '$seconds seconds',
        },
        width: 160,
      ),
      quietRepeatSettingId => _choice(
        setting,
        preferences.scheduleRepeat,
        _repeats,
      ),
      quietStartSettingId => _time(setting, preferences.scheduleStart),
      quietEndSettingId => _time(setting, preferences.scheduleEnd),
      priorityAppsSettingId => _apps(setting, preferences.priorityApps),
      _ => SettingControlTile(setting),
    };
  }

  // Schedule details are hidden while the schedule is off.
  bool _visible(SettingSpec setting) =>
      _preferences?.schedule != false ||
      !const {
        quietStartSettingId,
        quietEndSettingId,
        quietRepeatSettingId,
      }.contains(setting.id);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      Text(
        widget.page.description,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 12),
      Text(widget.page.reason, style: Theme.of(context).textTheme.bodySmall),
      if (_error case final error?)
        SettingsErrorCard(message: error, onRetry: _busy ? null : _load),
      if (_preferences == null && _error == null)
        const Padding(
          padding: .only(top: 16),
          child: LinearProgressIndicator(),
        ),
      for (final section in widget.page.sections)
        SettingsSectionCard(
          section,
          onPageRow: (_) {},
          pageRows: const {},
          controlBuilder: _control,
          isVisible: _visible,
        ),
      if (widget.page.children.isNotEmpty) ...[
        const SettingsSectionTitle('Related settings'),
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              for (final id in widget.page.children)
                PageLink(
                  page: widget.catalog.page(id),
                  icon: categoryIcon(
                    widget.catalog.category(widget.page.category).icon,
                  ),
                  onTap: () => widget.onPage(widget.catalog.page(id)),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}

/// Installed desktop applications, filtered by name.
class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.client, required this.exclude});

  final SettingsClient client;
  final Set<String> exclude;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  late final Future<List<PriorityApp>> _apps = _read();
  String _query = '';

  Future<List<PriorityApp>> _read() async {
    final data = await widget.client.readInstalledApplications();
    final apps = <String, PriorityApp>{};
    for (final app in data['applications'] as List? ?? const []) {
      if (app case {'id': final String id, 'name': final String name}) {
        // Notifications name their desktop entry without the suffix.
        final entry = id.endsWith('.desktop')
            ? id.substring(0, id.length - 8)
            : id;
        if (!widget.exclude.contains(entry)) {
          apps[entry] = (id: entry, name: name);
        }
      }
    }
    return apps.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add priority app'),
    content: SizedBox(
      width: 420,
      height: 420,
      child: Column(
        spacing: 12,
        children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Search apps',
            ),
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
          ),
          Expanded(
            child: FutureBuilder<List<PriorityApp>>(
              future: _apps,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text('${snapshot.error}');
                final apps = snapshot.data;
                if (apps == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final shown = [
                  for (final app in apps)
                    if (app.name.toLowerCase().contains(_query) ||
                        app.id.toLowerCase().contains(_query))
                      app,
                ];
                if (shown.isEmpty) {
                  return const Center(child: Text('No matching apps'));
                }
                return ListView.builder(
                  itemCount: shown.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(shown[index].name),
                    subtitle: Text(shown[index].id),
                    onTap: () => Navigator.pop(context, shown[index]),
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
        child: const Text('Cancel'),
      ),
    ],
  );
}
