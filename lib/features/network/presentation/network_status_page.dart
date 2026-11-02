import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/network_controller.dart';
import 'network_widgets.dart';

const _historyLength = 60;

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond < 1000) return '${bytesPerSecond.round()} B/s';
  if (bytesPerSecond < 1000000) {
    return '${(bytesPerSecond / 1000).toStringAsFixed(1)} KB/s';
  }
  if (bytesPerSecond < 1000000000) {
    return '${(bytesPerSecond / 1000000).toStringAsFixed(1)} MB/s';
  }
  return '${(bytesPerSecond / 1000000000).toStringAsFixed(1)} GB/s';
}

class NetworkStatusPage extends StatefulWidget {
  const NetworkStatusPage({
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
  State<NetworkStatusPage> createState() => _NetworkStatusPageState();
}

class _NetworkStatusPageState extends State<NetworkStatusPage> {
  Timer? _timer;
  final _watch = Stopwatch()..start();
  String? _interface;
  int? _lastDown;
  int? _lastUp;
  Duration _lastAt = .zero;
  final _down = <double>[];
  final _up = <double>[];

  NetworkController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _sample();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _sample());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sample() async {
    if (_controller.primaryDevice == null) return;
    final Map<String, dynamic> traffic;
    try {
      traffic = await _controller.readTraffic();
    } catch (_) {
      return; // The next tick retries; connection errors are reported elsewhere.
    }
    if (!mounted) return;
    final down = traffic['rx_bytes'] as int?;
    final up = traffic['tx_bytes'] as int?;
    final now = _watch.elapsed;
    final seconds = (now - _lastAt).inMilliseconds / 1000;
    setState(() {
      if (traffic['interface'] != _interface) {
        _interface = traffic['interface'] as String?;
        _lastDown = _lastUp = null;
        _down.clear();
        _up.clear();
      }
      if (down != null && up != null && _lastDown != null && seconds > 0) {
        // Counters restart when an adapter comes back up.
        _push(_down, ((down - _lastDown!) / seconds).clamp(0, double.infinity));
        _push(_up, ((up - _lastUp!) / seconds).clamp(0, double.infinity));
      }
      _lastDown = down;
      _lastUp = up;
      _lastAt = now;
    });
  }

  void _push(List<double> history, num value) {
    history.add(value.toDouble());
    if (history.length > _historyLength) history.removeAt(0);
  }

  String get _status => switch (_controller.connectivity) {
    'full' => 'Connected to the internet',
    'limited' => 'Limited internet access',
    'portal' => 'Sign-in required for internet access',
    'none' => 'No internet access',
    _ =>
      _controller.primaryDevice == null
          ? 'Connect to a network to get online'
          : 'Connected; internet access not checked',
  };

  String _type(String? kind) => switch (kind) {
    'wifi' => 'Wi-Fi',
    'ethernet' => 'Ethernet',
    'bluetooth' => 'Bluetooth',
    'modem' => 'Mobile broadband',
    'wireguard' || 'tun' => 'VPN or tunnel',
    'bridge' => 'Bridge',
    _ => 'Other',
  };

  IconData _icon(String? kind) => switch (kind) {
    'wifi' => Icons.wifi_rounded,
    'ethernet' => Icons.lan_outlined,
    'bluetooth' => Icons.bluetooth_rounded,
    'modem' => Icons.cell_tower_rounded,
    'wireguard' || 'tun' => Icons.vpn_lock_outlined,
    _ => Icons.settings_ethernet_rounded,
  };

  String _stateLabel(Map device) => switch (device['state']) {
    'connected' => 'Connected',
    'connecting' => 'Connecting',
    'disconnecting' => 'Disconnecting',
    'disconnected' => 'Disconnected',
    'unavailable' => 'Unavailable',
    'unmanaged' => 'Not managed',
    'failed' => 'Failed',
    _ => 'Unknown',
  };

  Widget _hero(Map? primary) => NetworkHero(
    icon: primary == null
        ? Icons.signal_wifi_off_rounded
        : _icon(primary['kind'] as String?),
    title: primary?['connection'] as String? ?? 'Not connected',
    status: _status,
    action: _controller.canSignIn
        ? FilledButton(
            key: const ValueKey(networkSignInSettingId),
            onPressed: _controller.isBusy
                ? null
                : () => _controller.set(networkSignInSettingId, 'open'),
            child: const Text('Sign in'),
          )
        : null,
    children: [
      if (primary != null)
        LayoutBuilder(
          builder: (context, constraints) {
            final download = _SpeedTile(
              key: const ValueKey('network-status.traffic'),
              label: 'Download',
              icon: Icons.arrow_downward_rounded,
              history: _down,
            );
            final upload = _SpeedTile(
              label: 'Upload',
              icon: Icons.arrow_upward_rounded,
              history: _up,
            );
            return constraints.maxWidth < 480
                ? Column(
                    crossAxisAlignment: .stretch,
                    children: [download, const SizedBox(height: 12), upload],
                  )
                : Row(
                    children: [
                      Expanded(child: download),
                      const SizedBox(width: 12),
                      Expanded(child: upload),
                    ],
                  );
          },
        ),
    ],
  );

  Widget _adapter(Map device) {
    final colors = Theme.of(context).colorScheme;
    final connected = device['state'] == 'connected';
    return ListTile(
      key: ValueKey('adapter-${device['interface']}'),
      contentPadding: const .symmetric(horizontal: 20, vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: connected
              ? colors.secondaryContainer
              : colors.surfaceContainerHigh,
          shape: .circle,
        ),
        child: Icon(
          _icon(device['kind'] as String?),
          size: 22,
          color: connected
              ? colors.onSecondaryContainer
              : colors.onSurfaceVariant,
        ),
      ),
      title: Text(device['interface'] as String),
      subtitle: Text(
        [
          _type(device['kind'] as String?),
          if (device['connection'] case final String name) name,
          if (device['hardware_address'] case final String address) address,
        ].join('\n'),
      ),
      trailing: Text(
        _stateLabel(device),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: connected ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAvailable) {
      return NetworkUnavailable(controller: _controller);
    }
    final page = widget.page;
    final primary = _controller.primaryDevice;
    final physical = _controller.devices.where((d) => d['physical'] == true);
    final virtual = _controller.devices.where((d) => d['physical'] != true);
    String join(String key) =>
        (primary?[key] as List? ?? []).cast<String>().join('\n');
    final facts = <(String, String)>[
      if (primary != null) ...[
        ('Connection type', _type(primary['kind'] as String?)),
        if (join('ipv4').isNotEmpty) ('IPv4 address', join('ipv4')),
        if (primary['gateway'] case final String gateway) ('Gateway', gateway),
        if (join('dns').isNotEmpty) ('DNS servers', join('dns')),
        if (primary['speed_mbps'] case final int speed)
          ('Link speed', '$speed Mb/s'),
        if (primary['hardware_address'] case final String address)
          ('Hardware address', address),
        if (join('ipv6').isNotEmpty) ('IPv6 address', join('ipv6')),
      ],
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        _hero(primary),
        if (facts.isNotEmpty) ...[
          const NetworkSectionTitle('Connection details'),
          SettingsSurface(child: NetworkFacts(facts)),
        ],
        const NetworkSectionTitle('Adapters'),
        SettingsSurface(
          padding: .zero,
          child: physical.isEmpty
              ? const NetworkInfoRow(
                  id: 'network-status.adapters',
                  label: 'Network adapters',
                  value: 'No physical network adapters were detected',
                )
              : networkRows([for (final device in physical) _adapter(device)]),
        ),
        if (virtual.isNotEmpty)
          AdvancedSection(
            storageKey: const PageStorageKey('network-status-advanced'),
            child: KeyedSubtree(
              key: const PageStorageKey('network-status-advanced-body'),
              child: networkRows([
                for (final device in virtual) _adapter(device),
              ]),
            ),
          ),
        const NetworkSectionTitle('Related settings'),
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              SettingControlTile(
                page.controls.firstWhere(
                  (c) => c.id == 'network-status.data-usage',
                ),
                onOpenPage: () =>
                    widget.onPage(widget.catalog.page('data-usage')),
              ),
              for (final id in page.children)
                PageLink(
                  page: widget.catalog.page(id),
                  icon: categoryIcon(
                    widget.catalog.category(page.category).icon,
                  ),
                  onTap: () => widget.onPage(widget.catalog.page(id)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A current speed over its recent history.
class _SpeedTile extends StatelessWidget {
  const _SpeedTile({
    super.key,
    required this.label,
    required this.icon,
    required this.history,
  });
  final String label;
  final IconData icon;
  final List<double> history;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final value = history.isEmpty ? 'Measuring' : formatSpeed(history.last);
    return Semantics(
      label: '$label speed $value',
      container: true,
      child: Material(
        color: colors.surfaceContainerLowest,
        borderRadius: .circular(24),
        clipBehavior: .antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _SpeedPainter(history, colors.primary),
              ),
            ),
            Padding(
              padding: const .all(16),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: colors.primary),
                      const SizedBox(width: 6),
                      Text(label, style: text.labelLarge),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(value, style: text.headlineSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedPainter extends CustomPainter {
  _SpeedPainter(this.history, this.color)
    : _revision = history.isEmpty ? 0 : history.last,
      _length = history.length;
  final List<double> history;
  final Color color;
  final double _revision;
  final int _length;

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;
    final peak = history.reduce((a, b) => a > b ? a : b);
    if (peak <= 0) return;
    final step = size.width / (_historyLength - 1);
    final start = size.width - (history.length - 1) * step;
    final path = Path()..moveTo(start, size.height);
    for (var i = 0; i < history.length; i++) {
      // The lower half keeps the text above it readable.
      path.lineTo(
        start + i * step,
        size.height - history[i] / peak * size.height * 0.5,
      );
    }
    path
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.18));
  }

  @override
  bool shouldRepaint(_SpeedPainter old) =>
      old._revision != _revision || old._length != _length;
}
