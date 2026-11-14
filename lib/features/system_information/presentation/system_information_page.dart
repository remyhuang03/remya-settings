import '../application/hostname_controller.dart';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';

typedef _ReadResult = ({Map? values, String? error});

class SystemInformationPage extends StatefulWidget {
  const SystemInformationPage({super.key, required this.page, this.read});
  final SettingsPageSpec page;
  final SystemInformationReader? read;

  @override
  State<SystemInformationPage> createState() => _SystemInformationPageState();
}

class _SystemInformationPageState extends State<SystemInformationPage> {
  late Future<_ReadResult> _snapshot = _read();

  Future<_ReadResult> _read() async {
    try {
      final read = widget.read;
      if (read == null) {
        throw StateError('System information service unavailable');
      }
      await HostnameScope.maybeOf(context)?.reload();
      final snapshot = await read();
      return (values: snapshot['values'] as Map, error: null);
    } catch (error) {
      return (values: null, error: '$error');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_ReadResult>(
    future: _snapshot,
    builder: (context, snapshot) {
      final loading = snapshot.connectionState != .done;
      final values = snapshot.data?.values;
      final hostname = HostnameScope.maybeOf(context);
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'System information',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: loading
                    ? null
                    : () => setState(() {
                        _snapshot = _read();
                      }),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (loading) const LinearProgressIndicator(),
          if (snapshot.data?.error != null)
            Padding(
              padding: const .only(bottom: 16),
              child: Text(
                'Unable to read system information: ${snapshot.data!.error}',
              ),
            ),
          _DeviceCard(
            onRename: loading || hostname?.canRename != true
                ? null
                : () async {
                    final renamed = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _RenameDialog(controller: hostname!),
                    );
                    if (renamed == true && mounted) {
                      setState(() {
                        _snapshot = _read();
                      });
                    }
                  },
            field: hostname?.hostname == null
                ? (values?['about.4433eb13'] as Map?)
                : {'value': hostname!.hostname, 'error': null},
            loading: loading,
          ),
          for (final section in widget.page.sections.where(
            (s) => s.title != 'Device',
          )) ...[
            const SizedBox(height: 24),
            _InformationGroup(
              title: section.title,
              settings: section.controls,
              values: values,
              loading: loading,
            ),
          ],
        ],
      );
    },
  );
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.onRename,
    required this.field,
    required this.loading,
  });
  final VoidCallback? onRename;
  final Map? field;
  final bool loading;

  @override
  Widget build(BuildContext context) => SettingsSurface(
    padding: .zero,
    child: SettingRow(
      id: 'about.4433eb13',
      label: Row(
        mainAxisSize: .min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: .circular(20),
            ),
            child: Icon(
              Icons.computer_rounded,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              size: 28,
            ),
          ),
          const SizedBox(width: 20),
          Flexible(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  'Device name',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: .min,
                  children: [
                    Flexible(
                      child: SelectableText(
                        loading
                            ? 'Reading…'
                            : field?['value'] as String? ?? 'Unavailable',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('rename-hostname'),
                      tooltip: 'Rename device',
                      onPressed: onRename,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                if (!loading && field?['error'] != null)
                  Text('${field!['error']}'),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _InformationGroup extends StatelessWidget {
  const _InformationGroup({
    required this.title,
    required this.settings,
    required this.values,
    required this.loading,
  });
  final String title;
  final List<SettingSpec> settings;
  final Map? values;
  final bool loading;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      Padding(
        padding: const .only(left: 4, bottom: 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      ),
      SettingsSurface(
        padding: .zero,
        child: Column(
          children: [
            for (var index = 0; index < settings.length; index++) ...[
              if (index > 0)
                const Divider(height: 1, indent: 20, endIndent: 20),
              _InformationRow(
                setting: settings[index],
                field: values?[settings[index].id] as Map?,
                loading: loading,
              ),
            ],
          ],
        ),
      ),
    ],
  );
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.setting,
    required this.field,
    required this.loading,
  });
  final SettingSpec setting;
  final Map? field;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      setting.title,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
    final value = Column(
      crossAxisAlignment: .start,
      children: [
        SelectableText(
          loading ? 'Reading…' : field?['value'] as String? ?? 'Unavailable',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (!loading && field?['error'] != null)
          Text(
            '${field!['error']}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
    return Padding(
      key: ValueKey(setting.id),
      padding: const .symmetric(horizontal: 20, vertical: 18),
      child: SettingsRowLayout(left: label, right: value),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.controller});
  final HostnameController controller;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _initial = widget.controller.staticHostname?.isNotEmpty == true
      ? widget.controller.staticHostname!
      : widget.controller.hostname ?? '';
  late final _name = TextEditingController(text: _initial);
  String? _error;
  bool get _valid =>
      validateHostname(_name.text) == null && _name.text != _initial;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    if (!_valid || widget.controller.isBusy) return;
    setState(() {
      _error = null;
    });
    try {
      await widget.controller.rename(_name.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) => PopScope(
      canPop: !widget.controller.isBusy,
      child: AlertDialog(
        title: const Text('Rename this device'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                const Text(
                  'The new name takes effect immediately. Existing apps may need to be reopened.',
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('hostname-input'),
                  controller: _name,
                  autofocus: true,
                  enabled: !widget.controller.isBusy,
                  maxLength: 63,
                  decoration: InputDecoration(
                    labelText: 'Device name',
                    helperText: 'Lowercase letters, digits and hyphens',
                    helperMaxLines: 3,
                    errorText: validateHostname(_name.text),
                    errorMaxLines: 4,
                  ),
                  onChanged: (_) => setState(() {
                    _error = null;
                  }),
                  onSubmitted: (_) => _rename(),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (widget.controller.isBusy) const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: widget.controller.isBusy
                ? null
                : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _valid && !widget.controller.isBusy ? _rename : null,
            child: const Text('Rename'),
          ),
        ],
      ),
    ),
  );
}
