import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../application/network_controller.dart';
import 'network_widgets.dart';

const _vpnFiles = XTypeGroup(
  label: 'WireGuard or OpenVPN files',
  extensions: ['conf', 'ovpn'],
);

String _typeLabel(Map profile) => switch (profile['kind']) {
  'wireguard' => 'WireGuard',
  _ => switch (profile['vpn_type']) {
    'openvpn' => 'OpenVPN',
    'openconnect' => 'OpenConnect',
    'vpnc' => 'Cisco VPN (vpnc)',
    'strongswan' || 'libreswan' => 'IPsec',
    'l2tp' => 'L2TP',
    'pptp' => 'PPTP',
    final String type => type,
    _ => 'VPN',
  },
};

class VpnPage extends StatelessWidget {
  const VpnPage({super.key, required this.controller});
  final NetworkController controller;

  Future<void> _import() async {
    final path = (await openFile(acceptedTypeGroups: [_vpnFiles]))?.path;
    if (path != null) await controller.set(vpnImportSettingId, path);
  }

  Future<void> _remove(BuildContext context, Map profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${profile['name']}?'),
        content: const Text(
          'Its saved server, keys and credentials are removed from this device.',
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
      await controller.set(vpnRemoveSettingId, profile['uuid'] as String);
    }
  }

  Widget _row(BuildContext context, Map profile) {
    final colors = Theme.of(context).colorScheme;
    final connecting = profile['activating'] == true;
    final active = profile['active'] == true;
    return ListTile(
      key: ValueKey('vpn-${profile['uuid']}'),
      contentPadding: const .fromLTRB(20, 6, 12, 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: active ? colors.primaryContainer : colors.surfaceContainerHigh,
          shape: .circle,
        ),
        child: Icon(
          active ? Icons.vpn_lock_rounded : Icons.vpn_key_outlined,
          color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
        ),
      ),
      title: Text(profile['name'] as String),
      subtitle: Text(
        [
          _typeLabel(profile),
          if (connecting) 'Connecting' else if (active) 'Connected',
        ].join('\n'),
      ),
      trailing: Row(
        mainAxisSize: .min,
        children: [
          Switch(
            key: ValueKey('$vpnConnectSettingId-${profile['uuid']}'),
            value: active,
            onChanged:
                controller.isBusy || !controller.allowed('network-control')
                ? null
                : (value) => controller.set(
                    vpnConnectSettingId,
                    jsonEncode({'uuid': profile['uuid'], 'value': value}),
                  ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remove ${profile['name']}',
            onPressed:
                controller.isBusy ||
                    profile['read_only'] == true ||
                    !controller.allowed('settings.modify.system')
                ? null
                : () => _remove(context, profile),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!controller.isAvailable) {
      return NetworkUnavailable(controller: controller);
    }
    final profiles = controller.vpnProfiles;
    final active = profiles.where((p) => p['active'] == true).firstOrNull;
    final external = controller.externalTunnels;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        NetworkFailureBanner(controller: controller),
        NetworkHero(
          icon: active == null ? Icons.vpn_key_off_outlined : Icons.vpn_lock,
          title: active?['name'] as String? ?? 'No VPN connected',
          status: active == null
              ? 'Traffic goes directly through your network'
              : active['activating'] == true
              ? 'Connecting'
              : 'Traffic is sent through ${_typeLabel(active)}',
          children: [
            NetworkPath(
              key: const ValueKey('vpn.connections'),
              nodes: [
                (
                  icon: Icons.computer_outlined,
                  label: 'This device',
                  detail: null,
                ),
                if (active != null)
                  (
                    icon: Icons.vpn_lock_outlined,
                    label: 'VPN',
                    detail: active['name'] as String,
                  ),
                (icon: Icons.public_rounded, label: 'Internet', detail: null),
              ],
              links: [
                if (active != null)
                  active['activating'] == true
                      ? PathLink.degraded
                      : PathLink.working,
                controller.primaryDevice == null
                    ? PathLink.broken
                    : PathLink.working,
              ],
            ),
          ],
        ),
        SettingsSectionTitle(
          'VPN connections',
          trailing: FilledButton.icon(
            key: const ValueKey(vpnImportSettingId),
            onPressed:
                controller.isBusy ||
                    !controller.allowed('settings.modify.system')
                ? null
                : _import,
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import a VPN file'),
          ),
        ),
        SettingsSurface(
          padding: profiles.isEmpty ? const .all(20) : .zero,
          child: profiles.isEmpty
              ? const Text(
                  'No VPN connections yet. Import a WireGuard .conf file, or an OpenVPN .ovpn file when its NetworkManager plugin is installed. Imported connections start disconnected.',
                )
              : settingsRows([
                  for (final profile in profiles) _row(context, profile),
                ]),
        ),
        if (external.isNotEmpty) ...[
          const SettingsSectionTitle('Managed by other apps'),
          SettingsSurface(
            key: const ValueKey('vpn.external'),
            padding: .zero,
            child: settingsRows([
              for (final device in external)
                NetworkInfoRow(
                  id: 'vpn-external-${device['interface']}',
                  label: device['interface'] as String,
                  value: 'This tunnel is controlled by the app that created it, such as Tailscale.',
                ),
            ]),
          ),
        ],
      ],
    );
  }
}
