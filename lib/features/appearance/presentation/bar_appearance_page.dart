import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import '../../settings/presentation/settings_widgets.dart';

class BarAppearancePage extends StatefulWidget {
  const BarAppearancePage({
    super.key,
    required this.client,
    required this.page,
  });

  final SettingsClient client;
  final SettingsPageSpec page;

  @override
  State<BarAppearancePage> createState() => _BarAppearancePageState();
}

class _BarAppearancePageState extends State<BarAppearancePage> {
  bool? _showSeconds;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _update();
  }

  Future<void> _update([bool? enabled]) async {
    setState(() => _busy = true);
    try {
      final value = await (enabled == null
          ? widget.client.readBarClockSeconds()
          : widget.client.setBarClockSeconds(enabled));
      if (!mounted) return;
      setState(() {
        _showSeconds = value;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      if (_error case final error?)
        SettingsSurface(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(error),
              TextButton(
                onPressed: _busy ? null : () => _update(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      SettingsSectionCard(
        widget.page.sections.single,
        pageRows: const {},
        onPageRow: (_) {},
        controlBuilder: (setting) => SettingRow(
          id: setting.id,
          label: Text(
            setting.title,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          control: _showSeconds == null
              ? (_busy ? const CircularProgressIndicator() : null)
              : Semantics(
                  label: setting.title,
                  child: Switch(
                    value: _showSeconds!,
                    onChanged: _busy ? null : _update,
                  ),
                ),
        ),
      ),
    ],
  );
}
