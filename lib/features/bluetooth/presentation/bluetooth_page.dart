import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../../settings/presentation/settings_list.dart';
import '../application/bluetooth_controller.dart';

class BluetoothPage extends StatefulWidget {
  const BluetoothPage({super.key, required this.controller});
  final BluetoothController controller;
  @override
  State<BluetoothPage> createState() => _BluetoothPageState();
}

class _BluetoothPageState extends State<BluetoothPage> {
  BluetoothController get controller => widget.controller;
  @override
  void initState() {
    super.initState();
    controller.reload();
  }

  @override
  void dispose() {
    unawaited(controller.release());
    super.dispose();
  }

  Future<void> _add({bool visible = false}) async {
    await controller.scan(visible: visible);
    if (!mounted) {
      await controller.release();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _AddDeviceDialog(controller: controller),
    );
    await controller.release();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final adapter = controller.adapter;
      final paired = controller.devices
          .where((d) => d['paired'] == true || d['bonded'] == true)
          .toList();
      final indices = {
        for (var i = 0; i < paired.length; i++) ValueKey(paired[i]['id']): i,
      };
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          _BluetoothStatus(controller: controller),
          if (!controller.available)
            const SettingsSurface(
              child: Text(
                'Bluetooth is unavailable. Check that the system Bluetooth service is running.',
              ),
            )
          else if (adapter == null)
            const SettingsSurface(child: Text('No Bluetooth adapter found.'))
          else ...[
            if (controller.adapters.length > 1)
              SettingsSurface(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(adapter['id']),
                  initialValue: adapter['id'] as String,
                  decoration: const InputDecoration(labelText: 'Adapter'),
                  isExpanded: true,
                  items: [
                    for (final a in controller.adapters)
                      DropdownMenuItem(
                        value: a['id'] as String,
                        child: Text(
                          '${a['name']} (${a['address']})',
                          overflow: .ellipsis,
                        ),
                      ),
                  ],
                  onChanged:
                      controller.busy || adapter['hardware_blocked'] == true
                      ? null
                      : (id) {
                          if (id != null) controller.selectAdapter(id);
                        },
                ),
              ),
            SettingsSurface(
              child: SwitchListTile(
                contentPadding: .zero,
                title: const Text('Bluetooth'),
                subtitle: Text(
                  adapter['hardware_blocked'] == true
                      ? 'Blocked by a hardware switch'
                      : adapter['software_blocked'] == true
                      ? 'Blocked by system radio control'
                      : controller.powered
                      ? 'On'
                      : 'Off',
                ),
                value: controller.powered,
                onChanged:
                    controller.busy || adapter['hardware_blocked'] == true
                    ? null
                    : (enabled) => controller.set(bluetoothEnabledSettingId, {
                        'enabled': enabled,
                      }),
              ),
            ),
            if (controller.powered) ...[
              const SizedBox(height: 16),
              SettingsSurface(
                padding: .zero,
                child: SettingRow(
                  id: bluetoothDiscoverableSettingId,
                  label: Column(
                    crossAxisAlignment: .start,
                    children: [
                      const Text('Visible to nearby devices'),
                      const SizedBox(height: 4),
                      Text(
                        'Discoverable: ${adapter['discoverable'] == true ? 'Yes' : 'No'}',
                      ),
                      const Text(
                        'Allow nearby devices to find this computer for 60 seconds.',
                      ),
                    ],
                  ),
                  control: OutlinedButton.icon(
                    onPressed: controller.busy
                        ? null
                        : () => _add(visible: true),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Make visible'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SettingsList(
              title: 'Paired devices',
              actions: [
                if (controller.powered)
                  FilledButton.icon(
                    key: const ValueKey('bluetooth.add'),
                    onPressed: controller.busy ? null : _add,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add device'),
                  ),
              ],
              empty: const Text('No paired devices.'),
              itemCount: paired.length,
              findChildIndexCallback: (key) => indices[key],
              itemBuilder: (context, index) => _DeviceCard(
                key: ValueKey(paired[index]['id']),
                controller: controller,
                device: paired[index],
              ),
            ),
            const SizedBox(height: 16),
            AdvancedSection(
              storageKey: const PageStorageKey('bluetooth.advanced'),
              child: Padding(
                padding: const .all(20),
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text('Name: ${adapter['name']}'),
                    Text('Address: ${adapter['address']}'),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}

class _BluetoothStatus extends StatelessWidget {
  const _BluetoothStatus({required this.controller});
  final BluetoothController controller;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      if (controller.busy) ...[
        const LinearProgressIndicator(),
        Padding(
          padding: const .symmetric(vertical: 8),
          child: Text(
            'In progress: ${controller.operation?['kind'] ?? 'Bluetooth'}',
          ),
        ),
      ],
      if (controller.errorMessage case final error?)
        Padding(
          padding: const .only(bottom: 12),
          child: SettingsSurface(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                const Icon(Icons.error_outline_rounded),
                Text(error),
                TextButton.icon(
                  onPressed: controller.sending ? null : controller.reload,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

IconData _deviceIcon(Map device) => switch (device['icon']) {
  'input-keyboard' => Icons.keyboard_rounded,
  'input-mouse' => Icons.mouse_rounded,
  'audio-headphones' || 'audio-headset' => Icons.headphones_rounded,
  'audio-card' => Icons.speaker_rounded,
  'phone' => Icons.phone_android_rounded,
  _ => Icons.bluetooth_rounded,
};

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    super.key,
    required this.controller,
    required this.device,
    this.nearby = false,
  });
  final BluetoothController controller;
  final Map device;
  final bool nearby;
  Future<void> _forget(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${device['name']}?'),
        content: const Text(
          'You will need to pair this device again to use it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.device(bluetoothForgetSettingId, device);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = device['connected'] == true;
    final blocked = device['blocked'] == true;
    return Padding(
      padding: const .only(bottom: 12),
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            Row(
              children: [
                Icon(_deviceIcon(device)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        device['name'] as String? ?? 'Bluetooth device',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(device['address'] as String? ?? ''),
                      Text(
                        blocked
                            ? 'Blocked by system'
                            : connected
                            ? 'Connected'
                            : nearby
                            ? 'Not connected'
                            : 'Paired, not connected',
                      ),
                      if (device['battery'] case final num battery)
                        Text('Battery: $battery%'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (controller.powered && !blocked)
                  FilledButton.tonalIcon(
                    icon: Icon(
                      nearby
                          ? Icons.link_rounded
                          : connected
                          ? Icons.link_off_rounded
                          : Icons.link_rounded,
                    ),
                    onPressed: controller.busy
                        ? null
                        : () => controller.device(
                            nearby
                                ? bluetoothPairSettingId
                                : connected
                                ? bluetoothDisconnectSettingId
                                : bluetoothConnectSettingId,
                            device,
                          ),
                    label: Text(
                      nearby
                          ? 'Pair'
                          : connected
                          ? 'Disconnect'
                          : 'Connect',
                    ),
                  ),
                if (!nearby)
                  TextButton.icon(
                    style: destructiveTextButtonStyle(context),
                    onPressed: controller.busy ? null : () => _forget(context),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddDeviceDialog extends StatelessWidget {
  const _AddDeviceDialog({required this.controller});
  final BluetoothController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final nearby = controller.devices
          .where((d) => d['paired'] != true && d['bonded'] != true)
          .toList();
      final indices = {
        for (var i = 0; i < nearby.length; i++) ValueKey(nearby[i]['id']): i,
      };
      return AlertDialog(
        title: const Text('Add Bluetooth device'),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              const Text(
                'Put your device in pairing mode. Cached devices may be out of range.',
              ),
              const SizedBox(height: 12),
              _BluetoothStatus(controller: controller),
              if (controller.prompt case final prompt?)
                _PairingPrompt(
                  key: ValueKey(prompt['id']),
                  controller: controller,
                  prompt: prompt,
                ),
              if (controller.pairing)
                TextButton(
                  onPressed: controller.sending
                      ? null
                      : () => controller.set(bluetoothCancelSettingId),
                  child: const Text('Cancel pairing'),
                ),
              if (!controller.powered) const Text('Bluetooth is off.'),
              if (controller.powered)
                SizedBox(
                  height: (MediaQuery.sizeOf(context).height * .5).clamp(
                    240,
                    400,
                  ),
                  child: SettingsList(
                    title: controller.scanning ? 'Scanning…' : 'Scan stopped',
                    actions: [
                      IconButton(
                        tooltip: 'Scan again',
                        onPressed: controller.busy ? null : controller.scan,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                    empty: const Text('No nearby devices found.'),
                    itemCount: nearby.length,
                    findChildIndexCallback: (key) => indices[key],
                    itemBuilder: (context, index) => _DeviceCard(
                      key: ValueKey(nearby[index]['id']),
                      controller: controller,
                      device: nearby[index],
                      nearby: true,
                    ),
                  ),
                ),
              if (controller.operation?['kind'] == 'pair' &&
                  controller.operation?['status'] == 'completed')
                const Text('Device paired and connected.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
    },
  );
}

class _PairingPrompt extends StatefulWidget {
  const _PairingPrompt({
    super.key,
    required this.controller,
    required this.prompt,
  });
  final BluetoothController controller;
  final Map prompt;
  @override
  State<_PairingPrompt> createState() => _PairingPromptState();
}

class _PairingPromptState extends State<_PairingPrompt> {
  final _input = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _respond() async {
    final kind = widget.prompt['kind'];
    final value = _input.text;
    final passkey = int.tryParse(value);
    if (kind == 'RequestPinCode' &&
        !RegExp(r'^[a-zA-Z0-9]{1,16}$').hasMatch(value)) {
      setState(() => _error = 'Enter 1 to 16 letters or digits');
      return;
    }
    if (kind == 'RequestPasskey' &&
        (!RegExp(r'^\d{1,6}$').hasMatch(value) || passkey == null)) {
      setState(() => _error = 'Enter up to six digits');
      return;
    }
    await widget.controller.set(bluetoothRespondSettingId, {
      'request': widget.prompt['id'],
      'accept': true,
      if (kind == 'RequestPinCode') 'pin': value,
      if (kind == 'RequestPasskey') 'passkey': passkey,
    });
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.prompt['kind'] as String;
    final entry = kind == 'RequestPinCode' || kind == 'RequestPasskey';
    final display = kind.startsWith('Display');
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            entry
                ? 'Enter the pairing code'
                : kind == 'RequestConfirmation'
                ? 'Do these numbers match on your device?'
                : display
                ? 'Type this code on the Bluetooth device'
                : 'Allow pairing with this device?',
          ),
          if (widget.prompt['code'] case final String code)
            SelectableText(
              code,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          if (widget.prompt['entered'] case final num entered)
            Text('Digits entered: $entered'),
          if (widget.prompt['service'] case final String service)
            Text('Service: $service'),
          if (entry)
            TextField(
              controller: _input,
              autofocus: true,
              keyboardType: kind == 'RequestPasskey' ? .number : .text,
              maxLength: kind == 'RequestPasskey' ? 6 : 16,
              decoration: InputDecoration(
                labelText: 'Pairing code',
                errorText: _error,
              ),
              onSubmitted: (_) => _respond(),
            ),
          if (!display)
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: widget.controller.sending ? null : _respond,
                  child: Text(entry ? 'Submit' : 'Confirm'),
                ),
                TextButton(
                  onPressed: widget.controller.sending
                      ? null
                      : () => widget.controller.set(bluetoothRespondSettingId, {
                          'request': widget.prompt['id'],
                          'accept': false,
                        }),
                  child: const Text('Reject'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
