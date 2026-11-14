import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../application/network_controller.dart';
import 'network_widgets.dart';

bool _isIpv4(String text) =>
    InternetAddress.tryParse(text)?.type == InternetAddressType.IPv4;

/// IP and DNS assignment rows of one saved connection, each with its editor.
List<Widget> addressRows({
  required BuildContext context,
  required NetworkController controller,
  required Map profile,
  required String ipId,
  required String dnsId,
  required bool editable,
}) {
  final ip = Map<String, dynamic>.from(profile['ip'] as Map);
  final uuid = profile['uuid'] as String;
  Future<void> edit(String id, Widget dialog) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => dialog,
    );
    if (result != null) await controller.edit(id, uuid, result);
  }

  Widget row(String id, String title, String value, Widget dialog) =>
      SettingRow(
        id: id,
        label: Column(
          crossAxisAlignment: .start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        control: FilledButton.tonalIcon(
          onPressed: editable ? () => edit(id, dialog) : null,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Edit'),
        ),
      );
  return [
    row(ipId, 'IP assignment', ipSummary(ip), _IpDialog(ip: ip)),
    row(
      dnsId,
      'DNS server assignment',
      dnsSummary(ip),
      _DnsDialog(ip: ip, tls: controller.dnsOverTlsSupported),
    ),
  ];
}

class _IpDialog extends StatefulWidget {
  const _IpDialog({required this.ip});
  final Map<String, dynamic> ip;

  @override
  State<_IpDialog> createState() => _IpDialogState();
}

class _IpDialogState extends State<_IpDialog> {
  late bool _manual = widget.ip['ipv4'] == 'manual';
  late String _ipv6 = widget.ip['ipv6'] as String;
  late final List<String> _addresses = (widget.ip['addresses'] as List)
      .cast<String>();
  late final _address = TextEditingController(
    text: _addresses.firstOrNull?.split('/').first ?? '',
  );
  late final _prefix = TextEditingController(
    text: _addresses.firstOrNull?.split('/').last ?? '24',
  );
  late final _gateway = TextEditingController(
    text: widget.ip['gateway'] as String,
  );
  String? _addressProblem;
  String? _prefixProblem;
  String? _gatewayProblem;

  /// Other IPv4 methods, such as `shared`, are kept unless replaced here.
  bool get _editableMethod =>
      const {'auto', 'manual'}.contains(widget.ip['ipv4']);

  @override
  void dispose() {
    _address.dispose();
    _prefix.dispose();
    _gateway.dispose();
    super.dispose();
  }

  void _submit() {
    final prefix = int.tryParse(_prefix.text.trim());
    final gateway = _gateway.text.trim();
    setState(() {
      _addressProblem = _manual && !_isIpv4(_address.text.trim())
          ? 'Enter an IPv4 address'
          : null;
      _prefixProblem = _manual && (prefix == null || prefix < 1 || prefix > 32)
          ? 'Use 1 to 32'
          : null;
      _gatewayProblem = _manual && gateway.isNotEmpty && !_isIpv4(gateway)
          ? 'Enter an IPv4 address'
          : null;
    });
    if (_addressProblem != null ||
        _prefixProblem != null ||
        _gatewayProblem != null) {
      return;
    }
    final method = _manual
        ? 'manual'
        : _editableMethod
        ? 'auto'
        : widget.ip['ipv4'];
    Navigator.pop(context, {
      ...widget.ip,
      'ipv4': method,
      // Extra addresses set elsewhere are kept after the edited first one.
      'addresses': _manual
          ? ['${_address.text.trim()}/$prefix', ..._addresses.skip(1)]
          : <String>[],
      'gateway': _manual ? gateway : '',
      'ipv6': _ipv6,
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final otherIpv6 = !const {'auto', 'disabled'}.contains(widget.ip['ipv6']);
    return AlertDialog(
      title: const Text('Edit IP settings'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              Text('IPv4', style: text.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(
                      _editableMethod ? 'Automatic (DHCP)' : 'Keep current',
                    ),
                    icon: const Icon(Icons.auto_mode_rounded),
                  ),
                  const ButtonSegment(
                    value: true,
                    label: Text('Manual'),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ],
                selected: {_manual},
                onSelectionChanged: (value) =>
                    setState(() => _manual = value.single),
              ),
              if (_manual) ...[
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('ip-address'),
                  controller: _address,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'IP address',
                    hintText: '192.168.1.20',
                    errorText: _addressProblem,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('ip-prefix'),
                  controller: _prefix,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Subnet prefix length',
                    helperText: '24 means subnet mask 255.255.255.0',
                    errorText: _prefixProblem,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('ip-gateway'),
                  controller: _gateway,
                  decoration: InputDecoration(
                    labelText: 'Gateway',
                    hintText: '192.168.1.1',
                    errorText: _gatewayProblem,
                  ),
                ),
                if (_addresses.length > 1) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Additional addresses are kept:\n${_addresses.skip(1).join('\n')}',
                    style: text.bodySmall,
                  ),
                ],
              ],
              const SizedBox(height: 24),
              Text('IPv6', style: text.titleSmall),
              if (otherIpv6)
                Padding(
                  padding: const .only(top: 8),
                  child: Text(
                    'Set elsewhere: ${widget.ip['ipv6']}. Choose an option to replace it.',
                    style: text.bodySmall,
                  ),
                ),
              SwitchListTile(
                contentPadding: .zero,
                title: const Text('Use IPv6'),
                subtitle: const Text('Addresses are assigned automatically'),
                value: _ipv6 != 'disabled',
                onChanged: (value) =>
                    setState(() => _ipv6 = value ? 'auto' : 'disabled'),
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
}

class _DnsDialog extends StatefulWidget {
  const _DnsDialog({required this.ip, required this.tls});
  final Map<String, dynamic> ip;

  /// Whether DNS over TLS can take effect through systemd-resolved.
  final bool tls;

  @override
  State<_DnsDialog> createState() => _DnsDialogState();
}

class _DnsDialogState extends State<_DnsDialog> {
  late bool _manual = widget.ip['auto_dns'] != true;
  late String _tls = widget.ip['dns_over_tls'] as String;
  late final List<TextEditingController> _servers = [
    for (final server in (widget.ip['dns'] as List).cast<String>())
      TextEditingController(text: server),
    if ((widget.ip['dns'] as List).isEmpty) TextEditingController(),
  ];
  final _problems = <int, String>{};
  String? _listProblem;

  @override
  void dispose() {
    for (final server in _servers) {
      server.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final servers = [
      for (final server in _servers)
        if (server.text.trim().isNotEmpty) server.text.trim(),
    ];
    setState(() {
      _problems
        ..clear()
        ..addAll({
          for (var i = 0; i < _servers.length; i++)
            if (_servers[i].text.trim().isNotEmpty &&
                InternetAddress.tryParse(_servers[i].text.trim()) == null)
              i: 'Enter an IPv4 or IPv6 address',
        });
      _listProblem = _manual && servers.isEmpty
          ? 'Enter at least one DNS server'
          : null;
    });
    if (_problems.isNotEmpty || _listProblem != null) return;
    Navigator.pop(context, {
      ...widget.ip,
      'auto_dns': !_manual,
      'dns': servers,
      'dns_over_tls': _tls,
    });
  }

  String _label(int index) => switch (index) {
    0 when _manual => 'Preferred DNS',
    1 when _manual => 'Alternate DNS',
    _ when _manual => 'DNS server ${index + 1}',
    _ => 'Additional DNS server ${index + 1} (optional)',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Edit DNS settings'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Automatic (DHCP)'),
                  icon: Icon(Icons.auto_mode_rounded),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Manual'),
                  icon: Icon(Icons.edit_outlined),
                ),
              ],
              selected: {_manual},
              onSelectionChanged: (value) =>
                  setState(() => _manual = value.single),
            ),
            const SizedBox(height: 8),
            Text(
              _manual ? 'Only these servers resolve names on this connection.' : 'Servers from the network are used; any listed here are added.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            for (var i = 0; i < _servers.length; i++)
              Padding(
                padding: const .only(top: 16),
                child: TextField(
                  key: ValueKey('dns-$i'),
                  controller: _servers[i],
                  decoration: InputDecoration(
                    labelText: _label(i),
                    hintText: i == 0 ? '1.1.1.1' : null,
                    errorText: _problems[i],
                    suffixIcon: _servers.length > 1
                        ? IconButton(
                            tooltip: 'Remove this server',
                            onPressed: () =>
                                setState(() => _servers.removeAt(i).dispose()),
                            icon: const Icon(Icons.remove_circle_outline),
                          )
                        : null,
                  ),
                ),
              ),
            if (_listProblem case final problem?)
              Padding(
                padding: const .only(top: 8),
                child: Text(
                  problem,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Align(
              alignment: .centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _servers.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add server'),
              ),
            ),
            if (widget.tls) ...[
              const SizedBox(height: 8),
              DropdownMenu<String>(
                initialSelection: _tls,
                label: const Text('DNS over TLS'),
                expandedInsets: .zero,
                onSelected: (value) {
                  if (value != null) setState(() => _tls = value);
                },
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: 'default', label: 'System default'),
                  DropdownMenuEntry(value: 'no', label: 'Off'),
                  DropdownMenuEntry(
                    value: 'opportunistic',
                    label: 'When available',
                  ),
                  DropdownMenuEntry(value: 'yes', label: 'Required'),
                ],
              ),
            ],
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
