import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/sound_controller.dart';

const compositorBellSettingId = 'sound.compositor-bell';

const _bellTypes = XTypeGroup(
  label: 'Audio files',
  extensions: ['wav', 'ogg', 'oga'],
);

typedef BellFilePicker = Future<String?> Function();

Future<String?> _pickBellWithDialog() async =>
    (await openFile(acceptedTypeGroups: [_bellTypes]))?.path;

class SoundPage extends StatefulWidget {
  const SoundPage({
    super.key,
    required this.controller,
    required this.page,
    this.catalog,
    this.client,
    this.pickBellFile = _pickBellWithDialog,
  });
  final SoundController controller;
  final SettingsPageSpec page;
  final SettingsCatalog? catalog;
  final SettingsClient? client;
  final BellFilePicker pickBellFile;
  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  Timer? _timer;
  String _query = '';
  String _kind = 'All';
  late final _desktop =
      widget.page.id == 'sound-volume' && widget.client != null
      ? (FeatureOptionsController(widget.client!, feature: 'desktop')..reload())
      : null;

  SoundController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    controller.reload();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => controller.reload(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _desktop?.dispose();
    super.dispose();
  }

  Widget _search(String label) => SizedBox(
    width: 232,
    child: TextField(
      key: ValueKey('${widget.page.id}-search'),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.search_rounded),
      ),
      onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
    ),
  );
  Widget _refresh() => IconButton(
    tooltip: 'Refresh audio',
    onPressed: controller.isBusy ? null : controller.refresh,
    icon: const Icon(Icons.refresh_rounded),
  );
  Widget _devices() {
    final matches = controller.devices
        .where(
          (d) =>
              '${d['description']} ${d['name']}'.toLowerCase().contains(
                _query,
              ) &&
              (_kind == 'All' ||
                  d['direction'] == (_kind == 'Output' ? 'output' : 'input')),
        )
        .toList();
    final indices = {
      for (var i = 0; i < matches.length; i++)
        ValueKey('${matches[i]['direction']}:${matches[i]['name']}'): i,
    };
    return SettingsList(
      key: PageStorageKey(widget.page.id),
      title: '${matches.length} sound devices',
      actions: [
        _search('Search sound devices'),
        DropdownMenu<String>(
          width: 160,
          label: const Text('Device type'),
          initialSelection: _kind,
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: 'All', label: 'All'),
            DropdownMenuEntry(value: 'Output', label: 'Output'),
            DropdownMenuEntry(value: 'Input', label: 'Input'),
          ],
          onSelected: (v) {
            if (v != null) setState(() => _kind = v);
          },
        ),
        _refresh(),
      ],
      empty: const Text('No sound devices found'),
      itemCount: matches.length,
      findChildIndexCallback: (key) => indices[key],
      itemBuilder: (context, index) => _DeviceRow(
        key: ValueKey(
          '${matches[index]['direction']}:${matches[index]['name']}',
        ),
        device: matches[index],
        controller: controller,
        divider: index > 0,
      ),
    );
  }

  Widget _mixer() {
    final matches = controller.streams
        .where(
          (s) =>
              '${s['application']} ${s['name']}'.toLowerCase().contains(_query),
        )
        .toList();
    final indices = {
      for (var i = 0; i < matches.length; i++)
        ValueKey(
          '${matches[i]['direction']}:${matches[i]['index']}:${matches[i]['client']}',
        ): i,
    };
    return SettingsList(
      key: PageStorageKey(widget.page.id),
      title: 'Applications (${matches.length})',
      actions: [_search('Search audio applications'), _refresh()],
      empty: const Text('No applications are playing or recording audio'),
      itemCount: matches.length,
      findChildIndexCallback: (key) => indices[key],
      itemBuilder: (context, index) => _StreamRow(
        key: ValueKey(
          '${matches[index]['direction']}:${matches[index]['index']}:${matches[index]['client']}',
        ),
        stream: matches[index],
        controller: controller,
        divider: index > 0,
      ),
    );
  }

  Widget _direction(String direction) {
    final devices = controller.devicesFor(direction);
    final device = controller.selected(direction);
    final output = direction == 'output';
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SettingsSectionTitle(output ? 'Output' : 'Input'),
        SettingsSurface(
          padding: .zero,
          child: settingsRows([
            SettingRow(
              id: 'sound.$direction-device',
              label: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(
                    output ? 'Output device' : 'Input device',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (device == null)
                    Text(
                      output
                          ? 'No output device is available'
                          : 'No input device is available',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    _DeviceFacts(device),
                ],
              ),
              control: DropdownMenu<String>(
                key: ValueKey('sound-$direction-${device?['name']}'),
                width: 280,
                initialSelection: device?['name'] as String?,
                enabled: controller.canChange && devices.isNotEmpty,
                dropdownMenuEntries: [
                  for (final d in devices)
                    DropdownMenuEntry(
                      value: d['name'] as String,
                      label: d['description'] as String,
                    ),
                ],
                onSelected: (name) {
                  if (name != null) {
                    controller.set('sound.$direction-device', {'name': name});
                  }
                },
              ),
            ),
            if (device != null)
              ..._DeviceRow.controls(device, controller, primary: true),
          ]),
        ),
      ],
    );
  }

  SettingSpec? _setting(String id) {
    for (final setting in widget.page.controls) {
      if (setting.id == id) return setting;
    }
    return null;
  }

  Future<void> _pickBell(FeatureOptionsController desktop) async {
    final path = await widget.pickBellFile();
    if (path != null && path.isNotEmpty) {
      await desktop.set(compositorBellSettingId, path);
    }
  }

  Widget _compositorBellRow(
    SettingSpec setting,
    FeatureOptionsController? desktop,
  ) {
    final raw = desktop?.option(compositorBellSettingId) as String?;
    final enabled = desktop != null && desktop.canChange;
    final mode = switch (raw) {
      'default' => 'default',
      'none' || '' => 'none',
      final path? when path.isNotEmpty => 'custom',
      _ => null,
    };
    final customPath = mode == 'custom' ? raw : null;
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
          Text(setting.reason, style: Theme.of(context).textTheme.bodySmall),
          if (customPath != null)
            Text(
              'File: $customPath',
              key: const ValueKey('sound.compositor-bell-path'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: .center,
        children: [
          SegmentedButton<String>(
            key: const ValueKey('sound.compositor-bell-segments'),
            segments: const [
              ButtonSegment(value: 'default', label: Text('Default')),
              ButtonSegment(value: 'none', label: Text('Off')),
              ButtonSegment(value: 'custom', label: Text('Custom')),
            ],
            selected: {?mode},
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            onSelectionChanged: enabled
                ? (next) {
                    if (next.isEmpty) return;
                    final choice = next.first;
                    if (choice == 'custom') {
                      _pickBell(desktop);
                    } else if (choice != raw) {
                      desktop.set(compositorBellSettingId, choice);
                    }
                  }
                : null,
          ),
          if (customPath != null)
            OutlinedButton.icon(
              key: const ValueKey('sound.compositor-bell-browse'),
              onPressed: enabled ? () => _pickBell(desktop) : null,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Browse'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = _desktop;
    final bellSetting = _setting(compositorBellSettingId);
    final unavailable = widget.page.controls
        .where((s) => s.availability != .available)
        .toList();
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ?desktop]),
      builder: (context, _) => Column(
        crossAxisAlignment: .stretch,
        children: [
          if (controller.isBusy || (desktop?.isBusy ?? false))
            const LinearProgressIndicator(),
          if (desktop?.errorMessage case final error?)
            SettingsErrorCard(message: error, onRetry: desktop!.reload),
          if (desktop != null && desktop.isLoaded) ...[
            if (desktop.writeBlocked case final reason?)
              SettingsErrorCard(message: reason, onRetry: desktop.reload),
            if (desktop.hasConflict && widget.catalog != null)
              InputConflictCard(
                controls: widget.catalog!.pages.expand((p) => p.controls),
                controller: desktop,
                title: 'Desktop settings differ from saved Settings',
              ),
          ],
          if (!controller.available)
            const SettingsSurface(
              child: Text(
                'Audio service unavailable. Start PipeWire, pipewire-pulse and WirePlumber.',
              ),
            )
          else
            switch (widget.page.id) {
              'sound-volume' => Column(
                crossAxisAlignment: .stretch,
                children: [_direction('output'), _direction('input')],
              ),
              'volume-mixer' => _mixer(),
              _ => _devices(),
            },
          if (bellSetting != null || unavailable.isNotEmpty)
            AdvancedSection(
              storageKey: PageStorageKey('${widget.page.id}-advanced'),
              child: KeyedSubtree(
                key: PageStorageKey('${widget.page.id}-advanced-body'),
                child: settingsRows([
                  if (bellSetting != null)
                    _compositorBellRow(bellSetting, desktop),
                  for (final setting in unavailable)
                    SettingControlTile(setting),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Device facts as separate labeled lines.
class _DeviceFacts extends StatelessWidget {
  const _DeviceFacts(this.device);
  final Map device;

  @override
  Widget build(BuildContext context) => Text(
    'Sample rate: ${device['rate']} Hz\n'
    'Channels: ${device['channels']}\n'
    'State: ${device['state']}',
    style: Theme.of(context).textTheme.bodySmall,
  );
}

/// One device in the Devices list: its name and facts, then volume and mute rows.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.controller,
    required this.divider,
  });
  final Map device;
  final SoundController controller;
  final bool divider;

  static List<Widget> controls(
    Map device,
    SoundController controller, {
    bool primary = false,
  }) {
    final direction = device['direction'] as String;
    final request = <String, Object?>{
      'direction': direction,
      'name': device['name'],
    };
    return [
      _VolumeRow(
        value: SoundController.volume(device),
        enabled: controller.canChange,
        label: direction == 'output' ? 'Volume' : 'Input volume',
        onChanged: (v) => controller.set(
          primary ? 'sound.$direction-volume' : 'sound.device-volume',
          {...request, 'percent': v},
        ),
      ),
      _MuteRow(
        label: direction == 'output' ? 'Mute' : 'Mute microphone',
        value: SoundController.muted(device),
        onChanged: controller.canChange
            ? (value) => controller.set(
                primary ? 'sound.$direction-muted' : 'sound.device-muted',
                {...request, 'muted': value},
              )
            : null,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final output = device['direction'] == 'output';
    return _ListItem(
      divider: divider,
      icon: output ? Icons.volume_up_rounded : Icons.mic_rounded,
      title: device['description'] as String,
      details: _DeviceFacts(device),
      rows: controls(device, controller),
    );
  }
}

class _StreamRow extends StatelessWidget {
  const _StreamRow({
    super.key,
    required this.stream,
    required this.controller,
    required this.divider,
  });
  final Map stream;
  final SoundController controller;
  final bool divider;
  @override
  Widget build(BuildContext context) {
    final direction = stream['direction'] as String;
    final request = <String, Object?>{
      'direction': direction,
      'index': stream['index'],
      'client': stream['client'],
    };
    final enabled = !controller.isBusy && controller.available;
    return _ListItem(
      divider: divider,
      icon: direction == 'output'
          ? Icons.music_note_rounded
          : Icons.mic_rounded,
      title: stream['application'] as String,
      details: Text(
        '${direction == 'output' ? 'Playback' : 'Recording'}: ${stream['name']}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      rows: [
        if (stream['has_volume'] == true)
          _VolumeRow(
            value: SoundController.volume(stream),
            label: 'Application volume',
            enabled: enabled && stream['volume_writable'] == true,
            onChanged: (v) => controller.set('sound.stream-volume', {
              ...request,
              'percent': v,
            }),
          ),
        _MuteRow(
          label: 'Mute',
          value: SoundController.muted(stream),
          onChanged: enabled
              ? (v) => controller.set('sound.stream-muted', {
                  ...request,
                  'muted': v,
                })
              : null,
        ),
        SettingRow(
          id: 'sound.stream-device-${stream['index']}',
          label: Text(
            direction == 'output' ? 'Output device' : 'Input device',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          control: DropdownMenu<String>(
            key: ValueKey('stream-${stream['index']}-${stream['device']}'),
            width: 280,
            initialSelection: stream['device'] as String?,
            enabled: enabled,
            dropdownMenuEntries: [
              for (final d in controller.devicesFor(direction))
                DropdownMenuEntry(
                  value: d['name'] as String,
                  label: d['description'] as String,
                ),
            ],
            onSelected: (name) {
              if (name != null) {
                controller.set('sound.stream-device', {
                  ...request,
                  'device': name,
                });
              }
            },
          ),
        ),
      ],
    );
  }
}

/// A list entry: a heading with facts, then its setting rows.
class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.divider,
    required this.icon,
    required this.title,
    required this.details,
    required this.rows,
  });
  final bool divider;
  final IconData icon;
  final String title;
  final Widget details;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      if (divider) const Divider(height: 1),
      Padding(
        padding: const .fromLTRB(20, 18, 20, 0),
        child: Row(
          crossAxisAlignment: .start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  details,
                ],
              ),
            ),
          ],
        ),
      ),
      ...rows,
    ],
  );
}

class _MuteRow extends StatelessWidget {
  const _MuteRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
    id: label,
    label: Text(label, style: Theme.of(context).textTheme.bodyLarge),
    control: Switch(value: value, onChanged: onChanged),
  );
}

class _VolumeRow extends StatefulWidget {
  const _VolumeRow({
    required this.value,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });
  final double value;
  final bool enabled;
  final String label;
  final ValueChanged<double> onChanged;
  @override
  State<_VolumeRow> createState() => _VolumeRowState();
}

class _VolumeRowState extends State<_VolumeRow> {
  double? _draft;
  @override
  Widget build(BuildContext context) {
    final value = _draft ?? widget.value;
    return SettingRow(
      id: widget.label,
      label: Column(
        crossAxisAlignment: .start,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            '${value.round()}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      control: SizedBox(
        width: 280,
        child: Slider(
          value: value.clamp(0, 150),
          max: 150,
          semanticFormatterCallback: (v) => '${widget.label} ${v.round()}%',
          onChanged: widget.enabled ? (v) => setState(() => _draft = v) : null,
          onChangeEnd: widget.enabled
              ? (v) {
                  setState(() => _draft = null);
                  widget.onChanged(v.clamp(0, 150));
                }
              : null,
        ),
      ),
    );
  }
}
