import 'package:material_ui/material_ui.dart';

import '../../settings/presentation/settings_widgets.dart';
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
        SettingsSurface(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              const Icon(Icons.error_outline_rounded),
              Text(error),
              TextButton(
                onPressed: _busy ? null : _reload,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      if (_tools?.isEmpty == true)
        const SettingsSurface(
          child: Text(
            'No supported external settings application is installed.',
          ),
        ),
      if (_tools case final tools?)
        for (final tool in tools)
          Padding(
            padding: const .only(bottom: 12),
            child: SettingsSurface(
              padding: .zero,
              child: SettingRow(
                id: tool['id'] as String,
                label: Row(
                  children: [
                    ApplicationIcon(icon: tool['icon'] as String?),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: .start,
                        children: [
                          Text(tool['name'] as String),
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
                    : FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _open(tool['id'] as String),
                        icon: const Icon(Icons.open_in_new_rounded),
                        label: const Text('Open'),
                      ),
              ),
            ),
          ),
    ],
  );
}
