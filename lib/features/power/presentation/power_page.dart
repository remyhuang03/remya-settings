import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../../settings/presentation/settings_content.dart';

class PowerPage extends StatefulWidget {
  const PowerPage({
    super.key,
    required this.page,
    required this.client,
    required this.onPage,
  });
  final ValueChanged<String> onPage;
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
      'power.5e3af39c' || 'power.8b4c8522' => _choice(
        setting,
        timeouts[setting.id == 'power.5e3af39c' ? 'screen' : 'sleep'],
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
    _ => true,
  };

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
        if (_error != null)
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(_error!),
          ),
        if (_state['conflict'] == true)
          Card(
            child: Padding(
              padding: const .all(16),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  const Text('System power settings differ from Settings.'),
                  Text(
                    'Saved: ${_saved['profile']}   System: ${_system['profile']}',
                  ),
                  Text(
                    'Saved timeouts: ${_saved['timeouts']}\nSystem timeouts: $timeouts',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _attempt(
                                () => _client.resolvePower('system'),
                              ),
                        child: const Text('Adopt system'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _attempt(
                                () => _client.resolvePower('settings'),
                              ),
                        child: const Text('Apply Settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if ((_system['degraded'] as String? ?? '').isNotEmpty)
          Text('Performance limited: ${_system['degraded']}'),
        if (_state['history_error'] != null)
          Text('Battery history: ${_state['history_error']}'),
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
