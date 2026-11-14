import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import 'application_icon.dart';

class ExternalToolsPage extends StatefulWidget {
  const ExternalToolsPage({super.key, required this.read, required this.open});
  final Future<Map<String, dynamic>> Function() read;
  final Future<Map<String, dynamic>> Function(String) open;
  @override
  State<ExternalToolsPage> createState() => _ExternalToolsPageState();
}

class _ExternalToolsPageState extends State<ExternalToolsPage> {
  List<Map>? _tools;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final state = await widget.read();
      if (mounted) {
        setState(() {
          _tools = (state['tools'] as List).cast<Map>();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Future<void> _open(String id) async {
    setState(() => _busy = true);
    try {
      await widget.open(id);
      await _reload();
    } catch (error) {
      await _reload();
      if (mounted) setState(() => _error = '$error');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      const Text(
        'Open installed external settings applications. Each application manages its own configuration.',
      ),
      const SizedBox(height: 16),
      if (_tools == null && _error == null) const LinearProgressIndicator(),
      if (_busy) const LinearProgressIndicator(),
      if (_error case final error?)
        SettingsErrorCard(message: error, onRetry: _busy ? null : _reload),
      if (_tools?.isEmpty == true)
        const SettingsSurface(
          child: Text(
            'No supported external settings application is installed.',
          ),
        ),
      if (_tools case final tools? when tools.isNotEmpty)
        SettingsSurface(
          padding: .zero,
          child: settingsRows([
            for (final tool in tools)
              SettingRow(
                id: tool['id'] as String,
                label: Row(
                  mainAxisSize: .min,
                  children: [
                    ApplicationIcon(icon: tool['icon'] as String?),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            tool['name'] as String,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          if (tool['launch_error'] case final String error)
                            Text(
                              error,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                control: tool['launch_error'] != null
                    ? null
                    : FilledButton.tonalIcon(
                        onPressed: _busy
                            ? null
                            : () => _open(tool['id'] as String),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open'),
                      ),
              ),
          ]),
        ),
    ],
  );
}
