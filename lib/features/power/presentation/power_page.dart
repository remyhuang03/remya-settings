import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../input/application/hypr_options_controller.dart';
import '../../input/presentation/input_widgets.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../../settings/presentation/settings_content.dart';
import 'idle_timeline.dart';

class PowerPage extends StatefulWidget {
  const PowerPage({
    super.key,
    required this.page,
    required this.catalog,
    required this.client,
    required this.onPage,
  });
  final ValueChanged<String> onPage;
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;
  @override
  State<PowerPage> createState() => _PowerPageState();
}

class _PowerPageState extends State<PowerPage> {
  static const _pageRows = {
    'power.743773bd': 'battery-saver',
    'power.03bd05ee': 'battery-usage',
  };

  SettingsClient get _client => widget.client;
  Map<String, dynamic> _state = {};
  String? _error;
  bool _busy = false;
  bool _reloadPending = false;
  Timer? _timer;
  StreamSubscription<SettingsChange>? _changes;

  /// Display wake comes from the Settings-owned Hyprland `desktop` options.
  late final _desktop = widget.page.id == 'power'
      ? (HyprOptionsController(_client, feature: 'desktop')
          ..addListener(_rebuild)
          ..reload())
      : null;
  final _dragging = <String, double>{};

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Map get _system => _state['system'] as Map? ?? {};
  Map get _saved => _state['saved'] as Map? ?? {};
  int get _turnOnAt => _saved['threshold'] as int? ?? 0;
  int get _turnOffAt => _saved['off_threshold'] as int? ?? -1;
  bool get _enabled =>
      !_busy &&
      _state['available'] == true &&
      _state['conflict'] != true &&
      _state['error'] == null;
  @override
  void initState() {
    super.initState();
    _changes = _client.changes.listen((change) {
      if (change.topic != 'power' && change.topic != keepAwakeSettingId) return;
      if (_busy) {
        _reloadPending = true;
      } else {
        unawaited(_load());
      }
    }, onError: (Object error) => debugPrint('Power changes: $error'));
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  Future<void> _load() async {
    if (_busy) return;
    await _attempt(() async {
      final power = await _client.readPower();
      if (widget.page.id == 'power') {
        power['keep_awake'] = await _client.readKeepAwake();
      }
      return power;
    });
  }

  Future<void> _attempt(Future<Map<String, dynamic>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (mounted) {
        setState(() {
          _state = {..._state, ...result};
          _error = _state['error'] as String?;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_reloadPending) {
          _reloadPending = false;
          unawaited(_load());
        }
      }
    }
  }

  void _set(String id, Object value) =>
      _attempt(() => _client.setPower(id, value));
  @override
  void dispose() {
    _desktop?.dispose();
    _timer?.cancel();
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Widget _choice(
    SettingSpec setting,
    Object? selected,
    Map<Object, String> choices,
  ) {
    if (selected != null && !choices.containsKey(selected)) {
      choices = {...choices, selected: '$selected'};
    }
    return SettingRow(
      id: setting.id,
      label: Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
      control: DropdownMenu<Object>(
        key: ValueKey('${setting.id}-$selected'),
        width: 232,
        menuHeight: 300,
        initialSelection: selected,
        enabled: _enabled,
        dropdownMenuEntries: [
          for (final entry in choices.entries)
            DropdownMenuEntry(value: entry.key, label: entry.value),
        ],
        onSelected: (value) {
          if (value != null) _set(setting.id, value);
        },
      ),
    );
  }

  Widget _toggle(SettingSpec setting, bool value, {String? description}) =>
      SettingRow(
        id: setting.id,
        label: Column(
          crossAxisAlignment: .start,
          children: [
            Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
            if (description != null) ...[
              const SizedBox(height: 6),
              Text(description, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
        control: Switch(
          value: value,
          onChanged: _enabled ? (v) => _set(setting.id, v) : null,
        ),
      );

  Widget _control(SettingSpec setting) {
    final timeouts = _system['timeouts'] as Map? ?? {};
    return switch (setting.id) {
      keepAwakeSettingId => _keepAwake(setting),
      final id when _pageRows.containsKey(id) => SettingControlTile(
        setting,
        onOpenPage: () => widget.onPage(_pageRows[id]!),
      ),
      'power.5a4f0131' => _choice(setting, _system['profile'], {
        for (final p in _system['profiles'] as List? ?? [])
          p: switch (p) {
            'balanced' => 'Balanced',
            'power-saver' => 'Power saver',
            'performance' => 'Performance',
            _ => '$p',
          },
      }),
      'power.wake-key' ||
      'power.wake-pointer' when _desktop != null => InputRows(
        context,
        _desktop,
        _dragging,
        (_, _) {},
      ).build(setting, subtitle: setting.reason),
      'power.lock-before-sleep' => _toggle(
        setting,
        timeouts['lock_before_sleep'] == true,
        description: setting.reason,
      ),
      'power.5e3af39c' || 'power.8b4c8522' || 'power.lock-after' => _choice(
        setting,
        timeouts[switch (setting.id) {
          'power.5e3af39c' => 'screen',
          'power.lock-after' => 'lock',
          _ => 'sleep',
        }],
        {
          0: 'Never',
          60: '1 minute',
          300: '5 minutes',
          600: '10 minutes',
          1200: '20 minutes',
          1800: '30 minutes',
          3600: '1 hour',
        },
      ),
      'battery-saver.743773bd' => _toggle(
        setting,
        _system['profile'] == 'power-saver',
      ),
      energySaverOnThresholdId => _choice(setting, _turnOnAt, {
        0: 'Never',
        for (final percent in [10, 20, 30, 50])
          if (_turnOffAt <= 0 || percent < _turnOffAt) percent: '$percent%',
        100: 'Always',
      }),
      energySaverOffThresholdId => _choice(setting, _turnOffAt, {
        -1: 'Follow turn-on threshold',
        0: 'Never',
        for (final percent in [30, 50, 70, 80, 90, 100])
          if (percent > _turnOnAt) percent: '$percent%',
      }),
      'battery-saver.power-source' => _toggle(
        setting,
        _saved['include_ac'] == true,
      ),
      'battery-saver.07945503' => _toggle(
        setting,
        _saved['dim'] == true,
        description:
            'Reduce built-in screen brightness to 70% of its current level.',
      ),
      _ => SettingControlTile(setting),
    };
  }

  Widget _keepAwake(SettingSpec setting) {
    final awake = _state['keep_awake'] as Map?;
    final value = awake?['value'];
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            awake?['error'] as String? ?? setting.reason,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      control: Switch(
        value: value == true,
        onChanged: !_busy && value is bool
            ? (enabled) => _attempt(
                () async => {'keep_awake': await _client.setKeepAwake(enabled)},
              )
            : null,
      ),
    );
  }

  bool _visible(SettingSpec setting) => switch (setting.id) {
    'battery-saver.power-source' => _turnOnAt > 0,
    energySaverOffThresholdId => _turnOnAt > 0 && _turnOnAt < 100,
    'battery-saver.07945503' => _system['has_backlight'] == true,
    // `loginctl lock-session` does nothing until hypridle has a lock_cmd.
    'power.lock-after' || 'power.lock-before-sleep' => _canLock,
    'power.wake-key' || 'power.wake-pointer' => _desktop?.isLoaded == true,
    _ => true,
  };

  bool get _canLock => _system['can_lock'] == true;

  Widget _timeline(Map timeouts) {
    final timeline = IdleTimeline(
      screen: timeouts['screen'] as int? ?? 0,
      lock: _canLock ? timeouts['lock'] as int? ?? 0 : 0,
      sleep: timeouts['sleep'] as int? ?? 0,
      lockBeforeSleep: _canLock && timeouts['lock_before_sleep'] == true,
    );
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const .only(bottom: 8),
      child: SettingsSurface(
        child: Column(
          spacing: 8,
          children: [
            timeline,
            Text(timeline.caption, textAlign: .center, style: text.bodyMedium),
            if (!_canLock)
              Text(
                'Locking options appear once hypridle.conf sets lock_cmd in its general section.',
                textAlign: .center,
                style: text.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeouts = _system['timeouts'] as Map? ?? {};
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          widget.page.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        if (_error != null) SettingsErrorCard(message: _error!, onRetry: _load),
        if (_state['conflict'] == true)
          _PowerConflict(
            saved: _saved,
            system: {..._system, 'timeouts': timeouts},
            onResolve: _busy
                ? null
                : (source) => _attempt(() => _client.resolvePower(source)),
          ),
        if ((_system['degraded'] as String? ?? '').isNotEmpty)
          Text(
            'Performance limited: ${_system['degraded']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (_state['history_error'] != null)
          Text(
            'Battery history: ${_state['history_error']}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (_desktop case final desktop?) ...[
          if (desktop.errorMessage case final error?)
            SettingsErrorCard(message: error, onRetry: desktop.reload),
          if (desktop.hasConflict)
            InputConflictCard(
              controls: widget.catalog.pages.expand((p) => p.controls),
              controller: desktop,
              title: 'Blur, background and display wake differ from saved Settings',
            ),
        ],
        if (widget.page.id == 'power' && _system['timeouts'] is Map)
          _timeline(timeouts),
        for (final section in widget.page.sections)
          SettingsSectionCard(
            section,
            onPageRow: (_) {},
            pageRows: const {},
            controlBuilder: _control,
            isVisible: _visible,
          ),
      ],
    );
  }
}

/// Saved and system power values side by side, with both resolutions.
class _PowerConflict extends StatelessWidget {
  const _PowerConflict({
    required this.saved,
    required this.system,
    required this.onResolve,
  });
  final Map saved;
  final Map system;

  /// Receives `system` or `settings`; null while another change runs.
  final ValueChanged<String>? onResolve;

  static String _duration(Object? seconds) => switch (seconds) {
    0 => 'Never',
    final int s when s % 3600 == 0 => '${s ~/ 3600} h',
    final int s when s % 60 == 0 => '${s ~/ 60} min',
    final int s => '$s s',
    _ => 'Unknown',
  };

  static String _summary(Map values) {
    final timeouts = values['timeouts'] as Map? ?? {};
    return 'Power mode: ${values['profile'] ?? 'Unknown'}\n'
        'Turn off screen: ${_duration(timeouts['screen'])}\n'
        'Lock screen: ${_duration(timeouts['lock'])}\n'
        'Sleep: ${_duration(timeouts['sleep'])}\n'
        'Lock before sleep: ${timeouts['lock_before_sleep'] == true ? 'On' : 'Off'}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget column(String title, Map values) => Column(
      crossAxisAlignment: .start,
      children: [
        Text(title, style: text.labelLarge),
        Text(_summary(values), style: text.bodySmall),
      ],
    );
    return Padding(
      padding: const .only(bottom: 12),
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: colors.tertiary),
                const SizedBox(width: 16),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      'Power settings differ from saved Settings',
                      style: text.titleSmall,
                    ),
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 48,
              runSpacing: 12,
              children: [column('System', system), column('Settings', saved)],
            ),
            Wrap(
              alignment: .end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: onResolve == null
                      ? null
                      : () => onResolve!('system'),
                  child: const Text('Use system configuration'),
                ),
                FilledButton.tonal(
                  onPressed: onResolve == null
                      ? null
                      : () => onResolve!('settings'),
                  child: const Text('Apply Settings configuration'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
