import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_ui/settings_ui.dart';

import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import 'input_widgets.dart';

class TouchscreenPage extends StatefulWidget {
  const TouchscreenPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });

  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<TouchscreenPage> createState() => _TouchscreenPageState();
}

class _TouchscreenPageState extends State<TouchscreenPage> {
  late final _controller = FeatureOptionsController(widget.client)..reload();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final devices = _controller.names('touchscreens');
      final error = _controller.state['touch_error'] as String?;
      final unavailable = _controller.state['error'] != null;
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        hero: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            if (error != null && !unavailable)
              SettingsErrorCard(message: error, onRetry: _controller.reload),
            if (devices.isNotEmpty || !unavailable)
              _TouchscreenDevices(devices: devices),
          ],
        ),
        isVisible: (_) => devices.isNotEmpty && error == null,
        controlBuilder: (setting) =>
            _DisplayMapping(setting: setting, controller: _controller),
      );
    },
  );
}

class _TouchscreenDevices extends StatelessWidget {
  const _TouchscreenDevices({required this.devices});

  final List<String> devices;

  @override
  Widget build(BuildContext context) => SettingsSurface(
    child: devices.isEmpty
        ? const Text('No touchscreen detected')
        : Column(
            crossAxisAlignment: .start,
            spacing: 8,
            children: [
              Text(
                'Connected touchscreens',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final name in devices) Chip(label: Text(name))],
              ),
            ],
          ),
  );
}

class _DisplayMapping extends StatelessWidget {
  const _DisplayMapping({required this.setting, required this.controller});

  final SettingSpec setting;
  final FeatureOptionsController controller;

  @override
  Widget build(BuildContext context) {
    final value = controller.option(setting.id) as String?;
    final displays = {
      for (final display in controller.list('touch_displays'))
        display['name'] as String: display['description'] as String? ?? '',
    };
    final options = <SettingsChoiceOption<String>>[
      const .new(value: '[[Auto]]', label: 'Default'),
      if (value == '') const .new(value: '', label: 'Focused display'),
      for (final MapEntry(key: name, value: description) in displays.entries)
        .new(
          value: name,
          label: description.isEmpty ? name : '$name ($description)',
          leadingIcon: const Icon(Icons.desktop_windows_outlined),
        ),
    ];
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            'Applies to all touchscreens',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      control: Semantics(
        label: setting.title,
        child: SettingsDropdown<String>.options(
          key: ValueKey((value, controller.isBusy, displays.keys.join('\n'))),
          label: setting.title,
          width: 280,
          options: options,
          selected: options.any((entry) => entry.value == value) ? value : null,
          hintText: value == null ? 'Unknown' : '$value (not connected)',
          onSelected:
              controller.canChange &&
                  value != null &&
                  controller.state['error'] == null
              ? (next) {
                  if (next != value) controller.set(setting.id, next);
                }
              : null,
        ),
      ),
    );
  }
}
