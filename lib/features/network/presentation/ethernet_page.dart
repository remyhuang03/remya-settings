import 'package:material_ui/material_ui.dart';
import 'package:remya_client/remya_client.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../application/network_controller.dart';
import 'ip_settings.dart';
import 'network_widgets.dart';

class EthernetPage extends StatelessWidget {
  const EthernetPage({super.key, required this.controller});
  final NetworkController controller;

  @override
  Widget build(BuildContext context) {
    if (!controller.isAvailable) {
      return NetworkUnavailable(controller: controller);
    }
    final adapters = controller.ethernetDevices;
    if (adapters.isEmpty) {
      return const NetworkHero(
        key: ValueKey('ethernet.status'),
        icon: Icons.lan_outlined,
        title: 'No Ethernet adapter',
        status: 'Connect a wired network adapter to use Ethernet.',
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final (index, device) in adapters.indexed) ...[
          if (index > 0) const SizedBox(height: 32),
          _Adapter(controller: controller, device: device),
        ],
      ],
    );
  }
}

class _Adapter extends StatelessWidget {
  const _Adapter({required this.controller, required this.device});
  final NetworkController controller;
  final Map device;

  String get _interface => device['interface'] as String;

  /// The connected profile, or the saved one bound to this adapter.
  Map? get _profile {
    final wired = controller.profilesOf(const {'ethernet'});
    return controller.profile(device['uuid'] as String?) ??
        wired.where((p) => p['interface'] == _interface).firstOrNull ??
        wired.where((p) => p['interface'] == null).firstOrNull;
  }

  String get _status => switch (device['state']) {
    'connected' => [
      'Connected',
      if (device['speed_mbps'] case final int speed) '$speed Mb/s',
    ].join(', '),
    'connecting' => 'Connecting',
    'disconnecting' => 'Disconnecting',
    'unavailable' => 'Network cable unplugged',
    'unmanaged' => 'Managed outside NetworkManager',
    'failed' => 'Could not connect',
    _ => 'Disconnected',
  };

  Widget? _action() {
    final state = device['state'];
    if (state == 'unavailable' || state == 'unmanaged') return null;
    final connected = state == 'connected' || state == 'connecting';
    void toggle() => controller.set(
      ethernetConnectSettingId,
      '{"interface":"$_interface","value":${!connected}}',
    );
    final enabled = !controller.isBusy && controller.allowed('network-control');
    return connected
        ? FilledButton.tonalIcon(
            key: const ValueKey(ethernetConnectSettingId),
            onPressed: enabled ? toggle : null,
            icon: const Icon(Icons.link_off_rounded),
            label: const Text('Disconnect'),
          )
        : FilledButton.icon(
            key: const ValueKey(ethernetConnectSettingId),
            onPressed: enabled ? toggle : null,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Connect'),
          );
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    String join(String key) =>
        (device[key] as List? ?? []).cast<String>().join('\n');
    final facts = <(String, String)>[
      if (join('ipv4').isNotEmpty) ('IPv4 address', join('ipv4')),
      if (device['gateway'] case final String gateway) ('Gateway', gateway),
      if (join('dns').isNotEmpty) ('DNS servers', join('dns')),
      if (join('ipv6').isNotEmpty) ('IPv6 address', join('ipv6')),
      if (device['hardware_address'] case final String address)
        ('Hardware address', address),
    ];
    final editable =
        profile != null &&
        controller.canChangePreferences &&
        profile['read_only'] != true &&
        controller.allowed('settings.modify.system');
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        NetworkHero(
          key: const ValueKey('ethernet.status'),
          icon: device['state'] == 'unavailable'
              ? Icons.cable_rounded
              : Icons.lan_outlined,
          title: profile?['name'] as String? ?? _interface,
          status: '$_status\nAdapter $_interface',
          action: _action(),
        ),
        if (facts.isNotEmpty) ...[
          const SettingsSectionTitle('Connection details'),
          SettingsSurface(
            key: const ValueKey('ethernet.details'),
            child: NetworkFacts(facts),
          ),
        ],
        if (profile != null) ...[
          SettingsSectionTitle('Settings for ${profile['name']}'),
          SettingsSurface(
            padding: .zero,
            child: settingsRows([
              if (profile['read_only'] == true)
                const NetworkInfoRow(
                  id: 'ethernet.read-only',
                  label: 'Read-only',
                  value: 'This saved connection cannot be changed here',
                ),
              SettingRow(
                id: ethernetAutoconnectSettingId,
                label: const Text('Connect automatically'),
                control: Switch(
                  value: profile['autoconnect'] == true,
                  onChanged: editable
                      ? (value) => controller.edit(
                          ethernetAutoconnectSettingId,
                          profile['uuid'] as String,
                          value,
                        )
                      : null,
                ),
              ),
              SettingRow(
                id: ethernetMeteredSettingId,
                label: const Text('Metered connection'),
                control: DropdownMenu<String>(
                  width: 232,
                  key: ValueKey('ethernet-metered-${profile['metered']}'),
                  initialSelection: profile['metered'] as String,
                  enabled: editable,
                  onSelected: (value) {
                    if (value != null && value != profile['metered']) {
                      controller.edit(
                        ethernetMeteredSettingId,
                        profile['uuid'] as String,
                        value,
                      );
                    }
                  },
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 'automatic', label: 'Automatic'),
                    DropdownMenuEntry(value: 'yes', label: 'Metered'),
                    DropdownMenuEntry(value: 'no', label: 'Not metered'),
                  ],
                ),
              ),
              ...addressRows(
                context: context,
                controller: controller,
                profile: profile,
                ipId: ethernetIpSettingId,
                dnsId: ethernetDnsSettingId,
                editable: editable,
              ),
            ]),
          ),
        ],
      ],
    );
  }
}
