import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../../settings/presentation/settings_list.dart';
import '../application/network_controller.dart';
import 'network_widgets.dart';

class WifiPage extends StatefulWidget {
  const WifiPage({
    super.key,
    required this.controller,
    required this.catalog,
    required this.page,
    required this.onPage,
  });
  final NetworkController controller;
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final ValueChanged<SettingsPageSpec> onPage;

  @override
  State<WifiPage> createState() => _WifiPageState();
}

class _WifiPageState extends State<WifiPage> {
  Timer? _timer;
  NetworkController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // The list only stays fresh through scans, needed only while this page is open.
    _controller.scan();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _controller.scan(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _connect(Map network) async {
    final uuid = network['known_uuid'] as String?;
    final security = network['security'] as String;
    String? password;
    if (uuid == null && personalSecurity(security)) {
      password = await askNetworkPassword(
        context,
        network: network['ssid'] as String,
      );
      if (password == null) return;
    }
    await _controller.set(
      wifiConnectSettingId,
      connectRequest(
        uuid: uuid,
        ssid: network['ssid'] as String,
        password: password,
      ),
    );
  }

  String _radioStatus() {
    if (!_controller.wifiHardwareEnabled) {
      return 'Blocked by a hardware switch';
    }
    if (!_controller.allowed('enable-disable-wifi')) {
      return 'You are not allowed to change this on this system';
    }
    return _controller.wifiEnabled ? 'On' : 'Off';
  }

  Widget _radio() => SettingRow(
    id: wifiEnabledSettingId,
    label: Column(
      crossAxisAlignment: .start,
      children: [
        Text('Wi-Fi', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(_radioStatus(), style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
    control: Switch(
      value: _controller.wifiEnabled,
      onChanged:
          _controller.isBusy ||
              !_controller.wifiHardwareEnabled ||
              !_controller.allowed('enable-disable-wifi')
          ? null
          : (value) => _controller.set(wifiEnabledSettingId, '$value'),
    ),
  );

  Widget _adapter() => SettingRow(
    id: wifiAdapterSettingId,
    label: const Text('Adapter'),
    control: DropdownMenu<String>(
      initialSelection: _controller.adapter,
      enabled: !_controller.isBusy,
      onSelected: (value) {
        if (value != null) _controller.set(wifiAdapterSettingId, value);
      },
      dropdownMenuEntries: [
        for (final device in _controller.wifiAdapters)
          DropdownMenuEntry(
            value: device['interface'] as String,
            label: device['interface'] as String,
          ),
      ],
    ),
  );

  Widget _current(Map network) {
    final device = _controller.wifiAdapter!;
    final frequency = network['frequency'] as int;
    final signal = network['signal'] as int;
    return NetworkHero(
      key: const ValueKey('wifi.current'),
      icon: signalIcon(signal),
      title: network['ssid'] as String,
      status: 'Connected',
      action: FilledButton.icon(
        key: const ValueKey(wifiDisconnectSettingId),
        onPressed: _controller.isBusy || !_controller.allowed('network-control')
            ? null
            : () => _controller.set(wifiDisconnectSettingId, 'disconnect'),
        icon: const Icon(Icons.link_off_rounded),
        label: const Text('Disconnect'),
      ),
      children: [
        NetworkFacts([
          ('Signal', '$signal%'),
          ('Band', bandLabel(frequency)),
          ('Channel', '${channelOf(frequency)}'),
          if (device['speed_mbps'] != null)
            ('Link speed', '${device['speed_mbps']} Mb/s'),
          ('Security', securityLabel(network['security'] as String?)),
        ], columnWidth: 150),
      ],
    );
  }

  Widget _network(Map network) {
    final security = network['security'] as String;
    final known = network['known_uuid'] != null;
    final creatable = known || !const {'enterprise', 'wep'}.contains(security);
    final connecting = _controller.connecting == network['ssid'];
    return SettingRow(
      key: ValueKey('wifi-item-${network['ssid']}-$security'),
      id: 'network-${network['ssid']}-$security',
      label: Row(
        children: [
          Icon(signalIcon(network['signal'] as int)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  network['ssid'] as String,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    securityLabel(security),
                    'Signal: ${network['signal']}%',
                    if (known) 'Saved',
                    if (!creatable)
                      'Settings cannot create this type of network',
                  ].join('\n'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
      control: FilledButton.icon(
        icon: const Icon(Icons.wifi_rounded),
        onPressed:
            _controller.isBusy ||
                _controller.connecting != null ||
                !creatable ||
                !_controller.allowed('network-control')
            ? null
            : () => _connect(network),
        label: Text(connecting ? 'Connecting' : 'Connect'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAvailable) {
      return NetworkUnavailable(controller: _controller);
    }
    if (_controller.wifiAdapters.isEmpty) {
      return const SettingsSurface(
        padding: .zero,
        child: NetworkInfoRow(
          id: wifiEnabledSettingId,
          label: 'Wi-Fi',
          value: 'No Wi-Fi adapter was detected',
        ),
      );
    }
    final current = _controller.currentNetwork;
    final others = _controller.networks
        .where((n) => n['in_use'] != true)
        .toList();
    final indices = {
      for (var i = 0; i < others.length; i++)
        ValueKey('wifi-item-${others[i]['ssid']}-${others[i]['security']}'): i,
    };
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        NetworkFailureBanner(controller: _controller),
        SettingsSurface(
          padding: .zero,
          child: networkRows([
            _radio(),
            if (_controller.wifiAdapters.length > 1) _adapter(),
          ]),
        ),
        if (_controller.wifiEnabled) ...[
          if (current != null) ...[
            const SizedBox(height: 24),
            _current(current),
          ],
          const SizedBox(height: 24),
          SettingsList(
            title: 'Available networks',
            actions: [
              IconButton(
                key: const ValueKey(wifiRefreshSettingId),
                tooltip: 'Refresh',
                onPressed: _controller.isBusy
                    ? null
                    : () => _controller.set(wifiRefreshSettingId, 'scan'),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            empty: const Text('No other networks were found'),
            itemCount: others.length,
            findChildIndexCallback: (key) => indices[key],
            itemBuilder: (context, index) => _network(others[index]),
          ),
        ],
        const NetworkSectionTitle('Saved networks'),
        SettingsSurface(
          padding: .zero,
          child: PageLink(
            page: widget.catalog.page('known-networks'),
            icon: Icons.bookmark_outline_rounded,
            onTap: () => widget.onPage(widget.catalog.page('known-networks')),
          ),
        ),
      ],
    );
  }
}
