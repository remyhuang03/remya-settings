import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/presentation/settings_widgets.dart';

class AiProvidersPage extends StatefulWidget {
  const AiProvidersPage({super.key, required this.client});

  final SettingsClient client;

  @override
  State<AiProvidersPage> createState() => _AiProvidersPageState();
}

class _AiProvidersPageState extends State<AiProvidersPage> {
  Map<String, dynamic>? _settings;
  String? _error;
  String _search = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() => _update(widget.client.readAiProviders);

  Future<void> _update(
    Future<Map<String, dynamic>> Function() operation,
  ) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await operation();
      if (mounted) setState(() => _settings = settings);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = (_settings?['providers'] as List?)?.whereType<Map>() ?? [];
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        if (_error case final error?)
          SettingsErrorCard(message: error, onRetry: _busy ? null : _read),
        if (_busy) const LinearProgressIndicator(),
        if (_settings != null) ...[
          Row(
            spacing: 8,
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Find a provider',
                  ),
                  onChanged: (value) =>
                      setState(() => _search = value.trim().toLowerCase()),
                ),
              ),
              IconButton(
                tooltip: 'Refresh from CodexBar',
                onPressed: _busy ? null : _read,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          for (final row in rows)
            if (row['name'] case final String name
                when name.toLowerCase().contains(_search))
              SwitchListTile(
                title: Text(name),
                value: row['enabled'] == true,
                onChanged: _busy || row['editable'] != true
                    ? null
                    : (enabled) => _update(
                        () => widget.client.setAiProvider(
                          row['id'] as String,
                          enabled,
                        ),
                      ),
              ),
        ],
      ],
    );
  }
}
