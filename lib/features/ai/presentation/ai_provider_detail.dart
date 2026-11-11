import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/presentation/settings_widgets.dart';
import 'ai_widgets.dart';

/// One provider: usage, connection, models and links.
class AiProviderDetail extends StatefulWidget {
  const AiProviderDetail({
    super.key,
    required this.client,
    required this.row,
    required this.lowPercent,
    required this.onBack,
    required this.onChanged,
  });
  final SettingsClient client;
  final AiRow row;
  final int lowPercent;
  final VoidCallback onBack;

  /// Runs a service change through the page so its state stays current.
  final Future<void> Function(Future<Map<String, dynamic>> Function())
  onChanged;

  @override
  State<AiProviderDetail> createState() => _AiProviderDetailState();
}

class _AiProviderDetailState extends State<AiProviderDetail> {
  Map<String, dynamic>? _detail;
  String? _error;

  String get _id => widget.row['id'] as String;
  String get _name => (widget.row['name'] as String?) ?? _id;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await widget.client.readAiProvider(_id);
      if (mounted) setState(() => _detail = detail);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _change(Future<Map<String, dynamic>> Function() op) async {
    await widget.onChanged(op);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final row = widget.row;
    final usage = _detail?['usage'] as Map?;
    final windows = aiRows(row['windows']);
    final modelsDev = _detail?['modelsDev'] as Map?;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Row(
          spacing: 12,
          children: [
            IconButton(
              tooltip: 'Back',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            AiProviderLogo(id: _id, name: _name, size: 56),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                spacing: 4,
                children: [
                  Text(_name, style: text.headlineSmall),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (row['plan'] case final String plan) AiChip(plan),
                      if (aiSourceLabel(row['source']) case final s?) AiChip(s),
                      AiChip(
                        aiStatus(row),
                        error: const {
                          'needs-setup',
                          'error',
                        }.contains(row['status']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_error case final message?)
          Padding(
            padding: const .only(top: 16),
            child: SettingsErrorCard(message: message, onRetry: _load),
          ),
        if (windows.isNotEmpty) ...[
          const SettingsSectionTitle('Usage'),
          SettingsSurface(
            child: Column(
              crossAxisAlignment: .stretch,
              spacing: 20,
              children: [
                for (final window in windows)
                  AiQuotaMeter(
                    id: _id,
                    window: window,
                    lowPercent: widget.lowPercent,
                  ),
                if ((usage?['credits'] as Map?)?['remaining'] case final num c
                    when c > 0)
                  Text('${c.toStringAsFixed(1)} credits left'),
              ],
            ),
          ),
        ],
        const SettingsSectionTitle('Connection'),
        SettingsSurface(
          padding: .zero,
          child: _Connection(
            client: widget.client,
            row: row,
            onChanged: _change,
          ),
        ),
        if (modelsDev != null) ...[
          SettingsSectionTitle(
            'Models',
            trailing: modelsDev['status'] == 'stale'
                ? Text('Saved copy', style: text.labelMedium)
                : null,
          ),
          _Models(modelsDev: modelsDev),
        ] else if (_detail == null && _error == null)
          const Padding(
            padding: .only(top: 24),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

class _Connection extends StatelessWidget {
  const _Connection({
    required this.client,
    required this.row,
    required this.onChanged,
  });
  final SettingsClient client;
  final AiRow row;
  final Future<void> Function(Future<Map<String, dynamic>> Function())
  onChanged;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final credential = (row['credential'] as Map?) ?? const {};
    final custom = row['kind'] == 'custom';
    final secret = custom || credential['apiKey'] == true
        ? 'API key'
        : credential['cookie'] == true
        ? 'Cookie header'
        : null;
    final modes = [
      for (final mode in (row['sourceModes'] as List?) ?? const [])
        if (mode is String) mode,
    ];
    final env = [
      for (final name in (row['envVars'] as List?) ?? const [])
        if (name is String) name,
    ];
    return settingsRows([
      if (custom)
        SettingRow(
          id: 'ai-base-url',
          label: _Field('Base URL', '${row['baseUrl']}'),
        ),
      if (!custom && modes.length > 1)
        SettingRow(
          id: 'ai-source',
          label: const _Field('Data source', 'Where CodexBar reads usage'),
          control: DropdownMenu<String>(
            initialSelection: modes.contains(row['source'])
                ? row['source'] as String
                : 'auto',
            dropdownMenuEntries: [
              for (final mode in modes)
                DropdownMenuEntry(
                  value: mode,
                  label: aiSourceLabel(mode) ?? 'Automatic',
                ),
            ],
            onSelected: (mode) {
              if (mode != null && mode != row['source']) {
                onChanged(() => client.setAiProvider(id, source: mode));
              }
            },
          ),
        ),
      if (secret != null)
        SettingRow(
          id: 'ai-credential',
          label: _Field(
            secret,
            credential['configured'] == true || custom ? 'Saved' : 'Not set',
          ),
          control: Wrap(
            spacing: 8,
            children: [
              if (credential['configured'] == true && !custom)
                TextButton(
                  style: destructiveTextButtonStyle(context),
                  onPressed: () =>
                      onChanged(() => client.setAiCredential(id, clear: true)),
                  child: const Text('Remove'),
                ),
              FilledButton.tonal(
                onPressed: () async {
                  final value = await _askSecret(context, secret);
                  if (value == null) return;
                  await onChanged(
                    () => client.setAiCredential(
                      id,
                      apiKey: secret == 'API key' ? value : null,
                      cookie: secret == 'API key' ? null : value,
                    ),
                  );
                },
                child: Text(
                  credential['configured'] == true || custom
                      ? 'Replace'
                      : 'Add',
                ),
              ),
            ],
          ),
        ),
      if (secret == null && modes.any(const {'cli', 'oauth'}.contains))
        const SettingRow(
          id: 'ai-cli-sign-in',
          label: _Field(
            'Sign-in',
            "Sign in with the provider's own CLI. CodexBar reads that session.",
          ),
        ),
      if (env.isNotEmpty)
        SettingRow(
          id: 'ai-env',
          label: _Field('Environment variables', env.join('\n')),
        ),
      if (custom)
        SettingRow(
          id: 'ai-remove',
          label: const _Field(
            'Remove endpoint',
            'Deletes its settings and saved API key',
          ),
          control: TextButton(
            style: destructiveTextButtonStyle(context),
            onPressed: () async {
              if (await _confirmRemove(context, '${row['name']}')) {
                await onChanged(() => client.removeAiCustomProvider(id));
              }
            },
            child: const Text('Remove'),
          ),
        ),
    ]);
  }
}

Future<String?> _askSecret(BuildContext context, String label) =>
    showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: 400,
            child: AiSecretField(
              controller: controller,
              label: label,
              autofocus: true,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) Navigator.pop(context, value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

Future<bool> _confirmRemove(BuildContext context, String name) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove $name?'),
        content: const Text('Its saved API key is deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    ) ==
    true;

class _Field extends StatelessWidget {
  const _Field(this.title, this.value);
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    spacing: 2,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class _Models extends StatefulWidget {
  const _Models({required this.modelsDev});
  final Map modelsDev;

  @override
  State<_Models> createState() => _ModelsState();
}

class _ModelsState extends State<_Models> {
  static const _shown = 8;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final provider = widget.modelsDev['provider'] as Map?;
    final models = aiRows(widget.modelsDev['models']);
    if (widget.modelsDev['status'] == 'unavailable' || provider == null) {
      return const SettingsSurface(
        child: Text('Model details are unavailable while offline.'),
      );
    }
    final visible = _all ? models : models.take(_shown).toList();
    return SettingsSurface(
      padding: .zero,
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          settingsRows([
            for (final model in visible)
              SettingRow(
                id: 'ai-model-${model['id']}',
                label: Column(
                  crossAxisAlignment: .start,
                  spacing: 2,
                  children: [
                    Text(
                      '${model['name'] ?? model['id']}',
                      style: text.titleSmall,
                    ),
                    Text(_modelFacts(model), style: text.bodySmall),
                  ],
                ),
              ),
          ]),
          if (models.length > _shown || provider['doc'] is String)
            Padding(
              padding: const .fromLTRB(12, 4, 12, 12),
              child: Wrap(
                spacing: 8,
                children: [
                  if (models.length > _shown)
                    TextButton(
                      onPressed: () => setState(() => _all = !_all),
                      child: Text(
                        _all ? 'Show fewer' : 'Show all ${models.length}',
                      ),
                    ),
                  if (provider['doc'] case final String doc)
                    TextButton.icon(
                      onPressed: () => Process.run('xdg-open', [doc]),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Documentation'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

String _modelFacts(AiRow model) {
  String tokens(num value) => value >= 1000000
      ? '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}M'
      : '${(value / 1000).round()}K';
  String price(num value) =>
      '\$${value.toStringAsFixed(value < 1
          ? 2
          : value.truncateToDouble() == value
          ? 0
          : 2)}';
  return [
    if (model['context'] case final num c when c > 0) '${tokens(c)} context',
    if ((model['input_cost'], model['output_cost']) case (
      final num i,
      final num o,
    ))
      '${price(i)} in, ${price(o)} out per 1M tokens',
    if (model['reasoning'] == true) 'Reasoning',
  ].join('\n');
}
