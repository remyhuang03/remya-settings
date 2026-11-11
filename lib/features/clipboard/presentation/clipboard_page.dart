import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import '../../settings/presentation/settings_widgets.dart';

class ClipboardPage extends StatefulWidget {
  const ClipboardPage({super.key, required this.client, required this.page});

  final SettingsClient? client;
  final SettingsPageSpec page;

  @override
  State<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends State<ClipboardPage> {
  ClipboardPreferences? _preferences;
  StreamSubscription<SettingsChange>? _changes;
  String? _error;
  bool _busy = false;
  bool _refreshPending = false;

  @override
  void initState() {
    super.initState();
    _changes = widget.client?.changes
        .where((change) => clipboardPreferenceIds.contains(change.topic))
        .listen((_) => unawaited(_refresh()), onError: (Object _) {});
    unawaited(_refresh());
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_busy) {
      _refreshPending = true;
      return;
    }
    await _run();
  }

  Future<bool> _run([Future<void> Function(SettingsClient)? change]) async {
    final client = widget.client;
    if (client == null || _busy) return false;
    setState(() => _busy = true);
    try {
      await change?.call(client);
      _refreshPending = false;
      final preferences = await client.readClipboardPreferences();
      if (mounted) {
        setState(() {
          _preferences = preferences;
          _error = null;
        });
      }
      return true;
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
      return false;
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_refreshPending) {
          _refreshPending = false;
          unawaited(_refresh());
        }
      }
    }
  }

  bool get _canChange => !_busy && _error == null && _preferences != null;

  Future<void> _changeLimit(SettingSpec setting, int current) async {
    final limit = await showDialog<int>(
      context: context,
      builder: (context) =>
          _EditLimitDialog(setting: setting, current: current),
    );
    if (limit == null || !mounted || !_canChange) return;
    await _run(
      (client) => setting.id == clipboardMaxItemsId
          ? client.setClipboardMaxItems(limit)
          : client.setClipboardRetentionDays(limit),
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear clipboard history?'),
        content: const Text(
          'This removes every entry from Remya Launcher’s history, including '
          'pinned entries.',
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear history'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_canChange) return;
    final cleared = await _run((client) => client.clearClipboardHistory());
    if (cleared && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard history cleared')),
      );
    }
  }

  Widget _limit(SettingSpec setting, int? value) => OutlinedButton(
    onPressed: value == null || !_canChange
        ? null
        : () => _changeLimit(setting, value),
    child: Text(value == null ? 'Unavailable' : '$value ${setting.unit}'),
  );

  Widget _row(SettingSpec setting) {
    final preferences = _preferences;
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
          Text(setting.reason, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      control: switch (setting.id) {
        clipboardHistoryEnabledId when preferences != null => Semantics(
          label: setting.title,
          child: Switch(
            value: preferences.enabled,
            onChanged: _canChange
                ? (value) =>
                      _run((client) => client.setClipboardHistoryEnabled(value))
                : null,
          ),
        ),
        clipboardMaxItemsId => _limit(setting, preferences?.maxItems),
        clipboardRetentionDaysId => _limit(setting, preferences?.retentionDays),
        clipboardClearHistoryId => FilledButton.tonal(
          style: destructiveTonalButtonStyle(context),
          onPressed: _canChange ? _clearHistory : null,
          child: const Text('Clear history'),
        ),
        _ => const Text('Unavailable'),
      },
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      if (widget.client == null)
        const SettingsErrorCard(message: 'The Settings service is unavailable.')
      else if (_error case final error?)
        SettingsErrorCard(message: error, onRetry: _busy ? null : _refresh)
      else if (_busy && _preferences == null)
        const LinearProgressIndicator(),
      if (!_busy || _preferences != null || _error != null)
        for (final section in widget.page.sections)
          SettingsSectionCard(
            section,
            onPageRow: (_) {},
            pageRows: const {},
            controlBuilder: _row,
          ),
    ],
  );
}

class _EditLimitDialog extends StatefulWidget {
  const _EditLimitDialog({required this.setting, required this.current});

  final SettingSpec setting;
  final int current;

  @override
  State<_EditLimitDialog> createState() => _EditLimitDialogState();
}

class _EditLimitDialogState extends State<_EditLimitDialog> {
  final _form = GlobalKey<FormState>();
  late int? _value = widget.current;

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, _value);
  }

  @override
  Widget build(BuildContext context) {
    final setting = widget.setting;
    final min = setting.min.toInt();
    final max = setting.max.toInt();
    return AlertDialog(
      title: Text(setting.title),
      content: Form(
        key: _form,
        child: TextFormField(
          autofocus: true,
          initialValue: '${widget.current}',
          keyboardType: .number,
          decoration: InputDecoration(
            labelText: 'Enter $min to $max ${setting.unit}',
          ),
          onChanged: (text) => _value = int.tryParse(text),
          onFieldSubmitted: (_) => _submit(),
          validator: (text) {
            final value = int.tryParse(text ?? '');
            return value == null || value < min || value > max
                ? 'Enter a whole number from $min to $max.'
                : null;
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Set limit')),
      ],
    );
  }
}
