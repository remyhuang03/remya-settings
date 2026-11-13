import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../application/network_controller.dart';
import 'network_widgets.dart';

String _bandLabel(String band) => switch (band) {
  '2.4' => '2.4 GHz',
  '5' => '5 GHz',
  _ => 'Any available',
};

class HotspotPage extends StatelessWidget {
  const HotspotPage({super.key, required this.controller});
  final NetworkController controller;

  Future<bool> _configure(BuildContext context, Map? hotspot) async {
    final request = await showDialog<Map<String, Object>>(
      context: context,
      builder: (_) => _HotspotDialog(
        hotspot: hotspot?['hotspot'] as Map?,
        bands: (controller.wifiAdapter?['bands'] as List? ?? []).cast<String>(),
      ),
    );
    if (request == null) return false;
    await controller.set(hotspotConfigureSettingId, jsonEncode(request));
    return controller.hotspotProfile != null;
  }

  Future<void> _toggle(BuildContext context, bool enabled) async {
    if (enabled &&
        controller.hotspotProfile == null &&
        !await _configure(context, null)) {
      return;
    }
    await controller.set(hotspotEnabledSettingId, '$enabled');
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.isAvailable) {
      return NetworkUnavailable(controller: controller);
    }
    final adapter = controller.wifiAdapter;
    final profile = controller.hotspotProfile;
    final info = profile?['hotspot'] as Map?;
    final active = profile?['active'] == true;
    final starting = profile?['activating'] == true;
    final primary = controller.primaryDevice;
    final source = primary?['connection'] as String?;
    final problem = adapter == null
        ? 'No Wi-Fi adapter was detected'
        : adapter['ap'] != true
        ? 'This Wi-Fi adapter cannot share a hotspot'
        : !controller.wifiEnabled
        ? 'Turn on Wi-Fi to share a hotspot'
        : null;
    // The adapter cannot join a network and host one at the same time.
    final replaces =
        !active &&
            primary != null &&
            primary['interface'] == adapter?['interface']
        ? primary['connection'] as String?
        : null;
    final canWrite =
        !controller.isBusy && controller.allowed('network-control');
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        NetworkFailureBanner(controller: controller),
        NetworkHero(
          icon: Icons.wifi_tethering_rounded,
          title: 'Mobile hotspot',
          status:
              problem ??
              (starting
                  ? 'Starting'
                  : active
                  ? 'Sharing as ${info?['ssid']}'
                  : 'Off'),
          action: problem == null
              ? Switch(
                  key: const ValueKey(hotspotEnabledSettingId),
                  value: active,
                  onChanged: canWrite
                      ? (value) => _toggle(context, value)
                      : null,
                )
              : null,
          children: [
            NetworkPath(
              key: const ValueKey('hotspot.source'),
              nodes: [
                (icon: Icons.public_rounded, label: 'Internet', detail: null),
                (
                  icon: Icons.computer_outlined,
                  label: 'This device',
                  detail: active ? source : source ?? 'Not connected',
                ),
                (
                  icon: Icons.devices_other_outlined,
                  label: 'Nearby devices',
                  detail: info?['ssid'] as String?,
                ),
              ],
              links: [
                primary == null || active && source == profile?['name']
                    ? PathLink.broken
                    : PathLink.working,
                starting
                    ? PathLink.degraded
                    : active
                    ? PathLink.working
                    : PathLink.broken,
              ],
            ),
          ],
        ),
        if (replaces != null && problem == null)
          Padding(
            padding: const .only(top: 16),
            child: SettingsSurface(
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Turning on the hotspot disconnects $replaces, because this adapter is also your internet connection.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SettingsSectionTitle('Hotspot network'),
        SettingsSurface(
          padding: .zero,
          child: settingsRows([
            NetworkInfoRow(
              id: 'hotspot.name',
              label: 'Network name',
              value: info?['ssid'] as String? ?? 'Not set up',
            ),
            if (info != null)
              NetworkInfoRow(
                id: 'hotspot.band',
                label: 'Network band',
                value: _bandLabel(info['band'] as String),
              ),
            NetworkInfoRow(
              id: 'hotspot.sharing',
              label: 'Sharing internet from',
              value: source == null || active && source == profile?['name']
                  ? 'No other connection'
                  : source,
            ),
            SettingRow(
              id: hotspotConfigureSettingId,
              label: const Text('Name, password and band'),
              control: FilledButton.tonalIcon(
                onPressed:
                    problem == null &&
                        controller.canChangePreferences &&
                        controller.allowed('settings.modify.system')
                    ? () => _configure(context, profile)
                    : null,
                icon: Icon(
                  info == null ? Icons.add_rounded : Icons.edit_outlined,
                ),
                label: Text(info == null ? 'Set up' : 'Edit'),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}

class _HotspotDialog extends StatefulWidget {
  const _HotspotDialog({required this.hotspot, required this.bands});
  final Map? hotspot;
  final List<String> bands;

  @override
  State<_HotspotDialog> createState() => _HotspotDialogState();
}

class _HotspotDialogState extends State<_HotspotDialog> {
  late final _name = TextEditingController(
    text: widget.hotspot?['ssid'] as String? ?? '',
  );
  final _password = TextEditingController();
  late String _band = widget.hotspot?['band'] as String? ?? 'auto';
  String? _nameProblem;
  String? _passwordProblem;

  bool get _creating => widget.hotspot == null;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final length = utf8.encode(_name.text).length;
    setState(() {
      _nameProblem = length < 1 || length > 32 ? 'Use 1 to 32 bytes' : null;
      _passwordProblem = _creating || _password.text.isNotEmpty
          ? passwordProblem(_password.text)
          : null;
    });
    if (_nameProblem != null || _passwordProblem != null) return;
    Navigator.pop(context, <String, Object>{
      'ssid': _name.text,
      'band': _band,
      if (_password.text.isNotEmpty) 'password': _password.text,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_creating ? 'Set up mobile hotspot' : 'Edit mobile hotspot'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Network name',
                errorText: _nameProblem,
              ),
            ),
            const SizedBox(height: 16),
            NetworkPasswordField(
              controller: _password,
              errorText: _passwordProblem,
            ),
            const SizedBox(height: 4),
            Text(
              _creating
                  ? 'Devices join with this WPA2 password. It is stored only in NetworkManager.'
                  : 'Leave empty to keep the current password.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('Network band', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                for (final band in ['auto', '2.4', '5'])
                  if (band == 'auto' || widget.bands.contains(band))
                    ButtonSegment(value: band, label: Text(_bandLabel(band))),
              ],
              selected: {_band},
              onSelectionChanged: (value) =>
                  setState(() => _band = value.single),
            ),
            const SizedBox(height: 4),
            Text(
              '2.4 GHz reaches farther and suits older devices; 5 GHz is faster nearby.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}
