import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_list.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/sound_controller.dart';

class SoundPage extends StatefulWidget {
  const SoundPage({super.key, required this.controller, required this.page});
  final SoundController controller;
  final SettingsPageSpec page;
  @override
  State<SoundPage> createState() => _SoundPageState();
}

class _SoundPageState extends State<SoundPage> {
  Timer? _timer;
  String _query = '';
  String _kind = 'All';
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
      ),
    );
  }

  Widget _direction(String direction) {
    final devices = controller.devicesFor(direction);
    final device = controller.selected(direction);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          direction == 'output' ? 'Output' : 'Input',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        SettingsSurface(
          padding: .zero,
          child: SettingRow(
            id: 'sound.$direction-device',
            label: Text(
              direction == 'output' ? 'Output device' : 'Input device',
            ),
            control: DropdownMenu<String>(
              key: ValueKey('sound-$direction-${device?['name']}'),
              width: 232,
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
        ),
        if (device == null) ...[
          const SizedBox(height: 16),
          Text(
            direction == 'output'
                ? 'No output device is available'
                : 'No input device is available',
          ),
        ] else ...[
          const SizedBox(height: 16),
          _DeviceRow(device: device, controller: controller, primary: true),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: .stretch,
      children: [
        if (controller.hasConflict)
          SettingsSurface(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                const Icon(Icons.warning_amber_rounded),
                const Text('Sound settings differ from saved Settings'),
                const Text(
                  'Device selection, volume or mute was changed outside Settings.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: controller.isBusy
                          ? null
                          : controller.useSystemConfiguration,
                      child: const Text('Use system configuration'),
                    ),
                    TextButton(
                      onPressed: controller.isBusy
                          ? null
                          : controller.applySavedConfiguration,
                      child: const Text('Apply saved Settings'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (controller.errorMessage case final error?)
          SettingsSurface(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                const Icon(Icons.error_outline_rounded),
                Text(error),
                TextButton.icon(
                  onPressed: controller.isBusy ? null : controller.refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        if (controller.isBusy) const LinearProgressIndicator(),
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
              children: [
                _direction('output'),
                const SizedBox(height: 24),
                _direction('input'),
              ],
            ),
            'volume-mixer' => _mixer(),
            _ => _devices(),
          },
        if (widget.page.controls.any((s) => s.availability != .available))
          AdvancedSection(
            storageKey: PageStorageKey('${widget.page.id}-advanced'),
            child: KeyedSubtree(
              key: PageStorageKey('${widget.page.id}-advanced-body'),
              child: Column(
                children: [
                  for (final setting in widget.page.controls.where(
                    (s) => s.availability != .available,
                  ))
                    SettingControlTile(setting),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    super.key,
    required this.device,
    required this.controller,
    this.primary = false,
  });
  final Map device;
  final SoundController controller;
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final direction = device['direction'] as String;
    final volume = SoundController.volume(device);
    final request = <String, Object?>{
      'direction': direction,
      'name': device['name'],
    };
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Icon(
                direction == 'output'
                    ? Icons.volume_up_rounded
                    : Icons.mic_rounded,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  device['description'] as String,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${direction == 'output' ? 'Output' : 'Input'}\n${device['rate']} Hz\n${device['channels']} channels\nState: ${device['state']}',
          ),
          _Volume(
            value: volume,
            enabled: controller.canChange,
            label: direction == 'output' ? 'Volume' : 'Input volume',
            onChanged: (v) => controller.set(
              primary ? 'sound.$direction-volume' : 'sound.device-volume',
              {...request, 'percent': v},
            ),
          ),
          SwitchListTile(
            contentPadding: .zero,
            title: Text(direction == 'output' ? 'Mute' : 'Mute microphone'),
            value: SoundController.muted(device),
            onChanged: controller.canChange
                ? (value) => controller.set(
                    primary ? 'sound.$direction-muted' : 'sound.device-muted',
                    {...request, 'muted': value},
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _StreamRow extends StatelessWidget {
  const _StreamRow({super.key, required this.stream, required this.controller});
  final Map stream;
  final SoundController controller;
  @override
  Widget build(BuildContext context) {
    final direction = stream['direction'] as String;
    final request = <String, Object?>{
      'direction': direction,
      'index': stream['index'],
      'client': stream['client'],
    };
    final enabled = !controller.isBusy && controller.available;
    return Padding(
      padding: const .all(20),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            stream['application'] as String,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            '${direction == 'output' ? 'Playback' : 'Recording'}\n${stream['name']}',
          ),
          if (stream['has_volume'] == true)
            _Volume(
              value: SoundController.volume(stream),
              label: 'Application volume',
              enabled: enabled && stream['volume_writable'] == true,
              onChanged: (v) => controller.set('sound.stream-volume', {
                ...request,
                'percent': v,
              }),
            ),
          SwitchListTile(
            contentPadding: .zero,
            title: const Text('Mute'),
            value: SoundController.muted(stream),
            onChanged: enabled
                ? (v) => controller.set('sound.stream-muted', {
                    ...request,
                    'muted': v,
                  })
                : null,
          ),
          DropdownMenu<String>(
            key: ValueKey('stream-${stream['index']}-${stream['device']}'),
            label: Text(
              direction == 'output' ? 'Output device' : 'Input device',
            ),
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
        ],
      ),
    );
  }
}

class _Volume extends StatefulWidget {
  const _Volume({
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
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  double? _draft;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      Text('${widget.label}: ${(_draft ?? widget.value).round()}%'),
      Slider(
        value: (_draft ?? widget.value).clamp(0, 150),
        max: 150,
        onChanged: widget.enabled ? (v) => setState(() => _draft = v) : null,
        onChangeEnd: widget.enabled
            ? (v) {
                setState(() => _draft = null);
                widget.onChanged(v.clamp(0, 150));
              }
            : null,
      ),
    ],
  );
}
