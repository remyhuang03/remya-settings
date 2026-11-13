import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import 'ai_widgets.dart';

/// Picks a provider from the catalog, or a custom endpoint, then saves its
/// credential. Pops `true` once something was added.
class AiAddProviderDialog extends StatefulWidget {
  const AiAddProviderDialog({
    super.key,
    required this.client,
    required this.catalog,
  });
  final SettingsClient client;
  final List<AiRow> catalog;

  @override
  State<AiAddProviderDialog> createState() => _AiAddProviderDialogState();
}

class _AiAddProviderDialogState extends State<AiAddProviderDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _secret = TextEditingController();
  String _search = '';
  AiRow? _picked;
  bool _custom = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _secret.dispose();
    super.dispose();
  }

  bool get _choosing => _picked == null && !_custom;
  bool get _endpoint => _custom || _picked?['kind'] == 'models-dev';

  void _pick(AiRow? row) => setState(() {
    _picked = row;
    _custom = row == null;
    _name.text = (row?['name'] as String?) ?? '';
    _url.text = (row?['baseUrl'] as String?) ?? '';
    _error = null;
  });

  /// The credential field a CodexBar provider accepts, if any.
  String? get _secretLabel {
    if (_endpoint) return 'API key';
    final credential = (_picked?['credential'] as Map?) ?? const {};
    if (credential['apiKey'] == true) return 'API key';
    if (credential['cookie'] == true) return 'Cookie header';
    return null;
  }

  String? _validate() {
    if (_endpoint) {
      if (_name.text.trim().isEmpty) return 'Enter a name.';
      final url = Uri.tryParse(_url.text.trim());
      final loopback = const {'localhost', '127.0.0.1', '::1'};
      if (url == null ||
          !url.hasAuthority ||
          !(url.isScheme('https') ||
              url.isScheme('http') && loopback.contains(url.host))) {
        return 'Enter an https URL, or http for this computer only.';
      }
    } else if (_secretLabel != null && _secret.text.trim().isEmpty) {
      return 'Enter the ${_secretLabel!.toLowerCase()}.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_validate() case final message?) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final secret = _secret.text.trim();
    try {
      if (_endpoint) {
        await widget.client.addAiCustomProvider(
          name: _name.text.trim(),
          baseUrl: _url.text.trim(),
          modelsDev: _picked?['modelsDev'] as String?,
          apiKey: secret.isEmpty ? null : secret,
        );
      } else {
        final id = _picked!['id'] as String;
        if (_secretLabel case final label?) {
          await widget.client.setAiCredential(
            id,
            apiKey: label == 'API key' ? secret : null,
            cookie: label == 'API key' ? null : secret,
          );
        }
        await widget.client.setAiProvider(id, enabled: true);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      _choosing
          ? 'Add provider'
          : _custom
          ? 'Custom endpoint'
          : '${_picked!['name']}',
    ),
    content: SizedBox(
      width: 480,
      height: _choosing ? 480 : null,
      child: _choosing ? _chooser(context) : _form(context),
    ),
    actions: [
      if (!_choosing)
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _picked = null;
                  _custom = false;
                }),
          child: const Text('Back'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      if (!_choosing)
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Add')),
    ],
  );

  Widget _chooser(BuildContext context) {
    final matches = [
      for (final row in widget.catalog)
        if ('${row['name']}'.toLowerCase().contains(_search)) row,
    ];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 8,
      children: [
        TextField(
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            labelText: 'Find a provider',
          ),
          onChanged: (value) =>
              setState(() => _search = value.trim().toLowerCase()),
        ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.link_rounded)),
          title: const Text('Custom endpoint'),
          subtitle: const Text('Any OpenAI-compatible API'),
          onTap: () => _pick(null),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: matches.length,
            itemBuilder: (context, i) {
              final row = matches[i];
              final id = row['id'] as String;
              final name = (row['name'] as String?) ?? id;
              return ListTile(
                leading: AiProviderLogo(
                  id: (row['modelsDev'] as String?) ?? id,
                  name: name,
                ),
                title: Text(name),
                subtitle: Text(
                  row['kind'] == 'codexbar'
                      ? 'Subscription and usage tracking'
                      : 'API endpoint',
                ),
                onTap: () => _pick(row),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final label = _secretLabel;
    final modes = (_picked?['sourceModes'] as List?) ?? const [];
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      spacing: 16,
      children: [
        if (_endpoint) ...[
          TextField(
            controller: _name,
            autofocus: _custom,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          TextField(
            controller: _url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.example.com/v1',
            ),
          ),
        ],
        if (label != null)
          AiSecretField(
            controller: _secret,
            label: _endpoint ? '$label (optional)' : label,
            autofocus: !_endpoint,
          ),
        if (!_endpoint && label == null)
          Text(
            modes.any(const {'cli', 'oauth'}.contains)
                ? "Sign in with the provider's own CLI first. CodexBar then "
                      'reads that session.'
                : 'CodexBar finds this provider automatically once it is set '
                      'up on this computer.',
          ),
        if (_endpoint)
          Text(
            'The API key is stored in your login keyring.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (_error case final message?)
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
