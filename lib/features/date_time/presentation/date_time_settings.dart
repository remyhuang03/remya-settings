import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../application/date_time_controller.dart';

class CurrentDateTime extends StatefulWidget {
  const CurrentDateTime({super.key});
  @override
  State<CurrentDateTime> createState() => _CurrentDateTimeState();
}

class _CurrentDateTimeState extends State<CurrentDateTime> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = DateTimeScope.maybeOf(context);
    final state = controller?.state;
    if (controller == null) return const SizedBox.shrink();
    return Padding(
      padding: const .only(bottom: 24),
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text(
            state == null
                ? 'System time unavailable'
                : DateTime.parse('${state.localTime}Z')
                      .add(
                        Duration(
                          microseconds:
                              DateTime.now().microsecondsSinceEpoch -
                              state.unixMicros.toInt(),
                        ),
                      )
                      .toIso8601String()
                      .substring(0, 19)
                      .replaceFirst('T', '  '),
            key: const ValueKey('current-date-time'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (state != null)
            Text(
              '${state.timezone} · Automatic time ${state.ntp ? 'on' : 'off'}',
            ),
        ],
      ),
    );
  }
}

class DateTimeSettingControl extends StatelessWidget {
  const DateTimeSettingControl(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context) {
    final controller = DateTimeScope.maybeOf(context);
    final state = controller?.state;
    if (controller == null || state == null) {
      return const SizedBox.shrink();
    }

    switch (id) {
      case timezoneSettingId:
      case timeLocaleSettingId:
        return _DateTimeChoice(
          key: ValueKey('choice-$id'),
          id: id,
          controller: controller,
        );
      case automaticTimeSettingId:
        return Switch(
          key: ValueKey('control-$id'),
          value: state.ntp,
          onChanged: (value) {
            if (!controller.isBusy) {
              _apply(() => controller.setAutomaticTime(value));
            }
          },
        );
      case timeServerSettingId:
        return _TimeServers(controller: controller);
      case syncNowSettingId:
        return _SyncNowButton(controller: controller);
    }
    return FilledButton(
      key: ValueKey('control-$id'),
      onPressed: controller.hideManualTime
          ? null
          : () {
              if (controller.isBusy) return;
              showDialog<void>(
                context: context,
                builder: (_) => _ManualTimeDialog(controller: controller),
              );
            },
      child: const Text('Set date and time'),
    );
  }
}

Future<void> _apply(Future<Object?> Function() action) async {
  try {
    await action();
  } catch (_) {
    /* The owning controller keeps the error visible. */
  }
}

class _SyncNowButton extends StatefulWidget {
  const _SyncNowButton({required this.controller});
  final DateTimeController controller;
  @override
  State<_SyncNowButton> createState() => _SyncNowButtonState();
}

class _SyncNowButtonState extends State<_SyncNowButton>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void initState() {
    super.initState();
    if (widget.controller.isSyncing) _rotation.repeat();
  }

  @override
  void didUpdateWidget(covariant _SyncNowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller.isSyncing) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      _rotation.reset();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final state = controller.state!;
    return Semantics(
      liveRegion: true,
      child: IconButton.filled(
        key: const ValueKey('control-$syncNowSettingId'),
        tooltip: controller.isSyncing ? 'Syncing…' : 'Sync now',
        onPressed: !controller.isSyncing && state.ntp && state.syncError == null
            ? () {
                if (!controller.isBusy) _apply(controller.syncNow);
              }
            : null,
        icon: RotationTransition(
          turns: _rotation,
          child: const Icon(Icons.sync_rounded),
        ),
      ),
    );
  }
}

class _DateTimeChoice extends StatefulWidget {
  const _DateTimeChoice({
    super.key,
    required this.id,
    required this.controller,
  });
  final String id;
  final DateTimeController controller;
  @override
  State<_DateTimeChoice> createState() => _DateTimeChoiceState();
}

class _DateTimeChoiceState extends State<_DateTimeChoice> {
  final _text = TextEditingController();
  String? _observed;
  bool get _timezone => widget.id == timezoneSettingId;
  String get _value => _timezone
      ? widget.controller.state!.timezone
      : widget.controller.state!.timeLocale;
  String _label(String value) => _timezone
      ? widget.controller.timezoneLabels[value]!
      : value.isEmpty
      ? 'System language default'
      : value;

  void _readValue() {
    if (_observed == _value) return;
    _observed = _value;
    _text.text = _label(_value);
  }

  @override
  void initState() {
    super.initState();
    _readValue();
  }

  @override
  void didUpdateWidget(covariant _DateTimeChoice oldWidget) {
    super.didUpdateWidget(oldWidget);
    _readValue();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _select(String? value) async {
    if (value != null && value != _value && !widget.controller.isBusy) {
      await _apply(
        () => _timezone
            ? widget.controller.setTimezone(value)
            : widget.controller.setTimeLocale(value),
      );
    }
    if (mounted) {
      _observed = _value;
      _text.text = _label(_value);
    }
  }

  Future<void> _chooseTimezone() async {
    final controller = widget.controller;
    if (controller.isBusy) return;
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _TimezonePicker(controller: controller),
    );
    if (mounted && !controller.isBusy) await _select(value);
  }

  @override
  Widget build(BuildContext context) {
    if (_timezone) {
      return FilledButton.icon(
        key: const ValueKey('timezone-combobox'),
        onPressed: widget.controller.isBusy ? null : _chooseTimezone,
        icon: const Icon(Icons.expand_more_rounded),
        label: Text(_label(_value)),
      );
    }
    return DropdownMenu<String>(
      key: const ValueKey('time-locale-combobox'),
      controller: _text,
      width: 232,
      menuHeight: 300,
      initialSelection: _value,
      dropdownMenuEntries: [
        for (final value in widget.controller.timeLocales)
          DropdownMenuEntry(value: value, label: _label(value)),
      ],
      onSelected: _select,
    );
  }
}

class _TimezonePicker extends StatefulWidget {
  const _TimezonePicker({required this.controller});
  final DateTimeController controller;
  @override
  State<_TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<_TimezonePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final matches = controller.timezones
        .where(
          (id) => controller.timezoneLabels[id]!.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    return AlertDialog(
      title: const Text('Choose a time zone'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: Column(
          children: [
            TextField(
              key: const ValueKey('timezone-search'),
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Search time zones',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => _query = value),
              onSubmitted: (_) {
                if (matches.length == 1) Navigator.pop(context, matches.single);
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No time zones found'))
                  : ListView.builder(
                      prototypeItem: const ListTile(
                        title: Text('UTC (GMT+00:00)', maxLines: 1),
                        trailing: Icon(Icons.check_rounded),
                      ),
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final id = matches[index];
                        return ListTile(
                          key: ValueKey('timezone-$id'),
                          selected: id == controller.state!.timezone,
                          title: Tooltip(
                            message: controller.timezoneLabels[id]!,
                            child: Text(
                              controller.timezoneLabels[id]!,
                              maxLines: 1,
                              overflow: .ellipsis,
                            ),
                          ),
                          trailing: id == controller.state!.timezone
                              ? const Icon(Icons.check_rounded)
                              : null,
                          onTap: () => Navigator.pop(context, id),
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

class _TimeServers extends StatefulWidget {
  const _TimeServers({required this.controller});
  final DateTimeController controller;
  @override
  State<_TimeServers> createState() => _TimeServersState();
}

class _TimeServersState extends State<_TimeServers> {
  late final _text = TextEditingController(
    text: widget.controller.state!.timeServers.join(' '),
  );
  late bool _custom = widget.controller.state!.timeServers.isNotEmpty;
  bool _saving = false;
  late String _observed = _text.text;
  @override
  void didUpdateWidget(covariant _TimeServers oldWidget) {
    super.didUpdateWidget(oldWidget);
    final value = widget.controller.state!.timeServers.join(' ');
    if (value != _observed) {
      _observed = value;
      _text.text = value;
      _custom = value.isNotEmpty;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || widget.controller.isBusy || _text.text.trim().isEmpty) {
      return;
    }
    final servers = _text.text.trim().split(RegExp(r'\s+'));
    if (servers.join(' ') == widget.controller.state!.timeServers.join(' ')) {
      return;
    }
    _saving = true;
    try {
      await _apply(() => widget.controller.setTimeServers(servers));
    } finally {
      _saving = false;
    }
  }

  Future<void> _useDefault() async {
    try {
      await widget.controller.setTimeServers([]);
    } catch (_) {
      if (mounted) {
        setState(
          () => _custom = widget.controller.state!.timeServers.isNotEmpty,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.controller.state!.ntp;
    return SizedBox(
      width: 232,
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: [
          DropdownMenu<bool>(
            key: const ValueKey('time-server-mode'),
            width: 232,
            initialSelection: _custom,
            enabled: enabled,
            dropdownMenuEntries: const [
              DropdownMenuEntry(value: false, label: 'Default'),
              DropdownMenuEntry(value: true, label: 'Custom'),
            ],
            onSelected: (value) {
              if (value == null || widget.controller.isBusy) return;
              setState(() => _custom = value);
              if (!value) _useDefault();
            },
          ),
          if (_custom) ...[
            const SizedBox(height: 8),
            Focus(
              onFocusChange: (focused) {
                if (!focused && enabled) _save();
              },
              child: TextField(
                key: const ValueKey('time-servers'),
                controller: _text,
                enabled: enabled,
                decoration: const InputDecoration(
                  hintText: 'pool.ntp.org',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _save(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManualTimeDialog extends StatefulWidget {
  const _ManualTimeDialog({required this.controller});
  final DateTimeController controller;
  @override
  State<_ManualTimeDialog> createState() => _ManualTimeDialogState();
}

class _ManualTimeDialogState extends State<_ManualTimeDialog> {
  late DateTime _date = DateTime.parse(widget.controller.state!.localTime);
  late TimeOfDay _time = TimeOfDay.fromDateTime(_date);
  late final String _timezone = widget.controller.state!.timezone;
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Set date and time'),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .stretch,
        children: [
          Text('Time zone: $_timezone'),
          const SizedBox(height: 12),
          const Text(
            'Applying a manual time turns off automatic time synchronization. System authorization may be required.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('manual-date'),
            onPressed: _busy
                ? null
                : () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(1971),
                      lastDate: DateTime(9999, 12, 31),
                    );
                    if (value != null && mounted) setState(() => _date = value);
                  },
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(_date.toIso8601String().substring(0, 10)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('manual-time'),
            onPressed: _busy
                ? null
                : () async {
                    final value = await showTimePicker(
                      context: context,
                      initialTime: _time,
                    );
                    if (value != null && mounted) setState(() => _time = value);
                  },
            icon: const Icon(Icons.schedule),
            label: Text(_time.format(context)),
          ),
          if (_busy)
            const Padding(
              padding: .only(top: 16),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const .only(top: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('apply-manual-time'),
        onPressed: _busy
            ? null
            : () async {
                setState(() {
                  _busy = true;
                  _error = null;
                });
                final value = DateTime.utc(
                  _date.year,
                  _date.month,
                  _date.day,
                  _time.hour,
                  _time.minute,
                ).toIso8601String().substring(0, 19);
                try {
                  await widget.controller.setManualTime(value, _timezone);
                  if (context.mounted) Navigator.pop(context);
                } catch (error) {
                  if (mounted) {
                    setState(() {
                      _error = '$error';
                      _busy = false;
                    });
                  }
                }
              },
        child: const Text('Apply'),
      ),
    ],
  );
}
