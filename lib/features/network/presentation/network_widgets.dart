import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/remya_client.dart';

import '../application/network_controller.dart';

String securityLabel(String? security) => switch (security) {
  'open' => 'Open',
  'owe' => 'Enhanced Open',
  'wep' => 'WEP (insecure)',
  'wpa' => 'WPA Personal',
  'wpa2' => 'WPA2/WPA3 Personal',
  'wpa3-transition' => 'WPA2/WPA3 Personal',
  'wpa3' => 'WPA3 Personal',
  'enterprise' => 'Enterprise',
  _ => 'Unknown',
};

bool personalSecurity(String? security) =>
    const {'wpa', 'wpa2', 'wpa3-transition', 'wpa3'}.contains(security);

String bandLabel(int frequency) => frequency >= 5925
    ? '6 GHz'
    : frequency >= 4900
    ? '5 GHz'
    : '2.4 GHz';

int channelOf(int frequency) => switch (frequency) {
  2484 => 14,
  >= 5925 => (frequency - 5950) ~/ 5,
  >= 4900 => (frequency - 5000) ~/ 5,
  _ => (frequency - 2407) ~/ 5,
};

IconData signalIcon(int signal) => signal >= 75
    ? Icons.network_wifi_rounded
    : signal >= 50
    ? Icons.network_wifi_3_bar_rounded
    : signal >= 25
    ? Icons.network_wifi_2_bar_rounded
    : Icons.network_wifi_1_bar_rounded;

/// One labeled fact in the information column.
class NetworkInfoRow extends StatelessWidget {
  const NetworkInfoRow({
    super.key,
    required this.id,
    required this.label,
    required this.value,
  });
  final String id;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SettingRow(
    id: id,
    label: Column(
      crossAxisAlignment: .start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}

/// NetworkManager is missing or unreadable; never replaced with sample values.
class NetworkUnavailable extends StatelessWidget {
  const NetworkUnavailable({super.key, required this.controller});
  final NetworkController controller;

  @override
  Widget build(BuildContext context) => SettingsSurface(
    child: Column(
      crossAxisAlignment: .start,
      children: [
        Text(
          'NetworkManager is unavailable',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          controller.errorMessage ?? 'Settings needs the NetworkManager service to read and change network connections.',
        ),
        const SizedBox(height: 16),
        FilledButton.tonal(
          onPressed: controller.reload,
          child: const Text('Try again'),
        ),
      ],
    ),
  );
}

/// Asks for a Wi-Fi password; the text is returned only to the caller.
Future<String?> askNetworkPassword(
  BuildContext context, {
  required String network,
  String? note,
}) => showDialog<String>(
  context: context,
  builder: (context) => _PasswordDialog(network: network, note: note),
);

String? passwordProblem(String password) {
  final hex =
      password.length == 64 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(password);
  if (hex) return null;
  final length = password.length;
  return length < 8 || length > 63 ? 'Use 8 to 63 characters' : null;
}

class NetworkPasswordField extends StatefulWidget {
  const NetworkPasswordField({
    super.key,
    required this.controller,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
  });
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;

  @override
  State<NetworkPasswordField> createState() => _NetworkPasswordFieldState();
}

class _NetworkPasswordFieldState extends State<NetworkPasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: true,
    obscureText: !_visible,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: widget.onChanged,
    onSubmitted: widget.onSubmitted,
    decoration: InputDecoration(
      labelText: 'Password',
      errorText: widget.errorText,
      suffixIcon: IconButton(
        tooltip: _visible ? 'Hide password' : 'Show password',
        onPressed: () => setState(() => _visible = !_visible),
        icon: Icon(
          _visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
      ),
    ),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.network, this.note});
  final String network;
  final String? note;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    final problem = passwordProblem(_password.text);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.network),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .start,
        children: [
          if (widget.note case final note?) ...[
            Text(note),
            const SizedBox(height: 16),
          ],
          NetworkPasswordField(
            controller: _password,
            errorText: _problem,
            onChanged: (_) {
              if (_problem != null) setState(() => _problem = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Connect')),
    ],
  );
}

String connectRequest({String? uuid, required String ssid, String? password}) =>
    jsonEncode({
      if (uuid != null) 'uuid': uuid else 'ssid': ssid,
      'password': ?password,
    });

/// The last connection attempt's failure, with a password retry when it can help.
class NetworkFailureBanner extends StatelessWidget {
  const NetworkFailureBanner({super.key, required this.controller});
  final NetworkController controller;

  Future<void> _retry(BuildContext context, Map failure) async {
    final ssid = failure['ssid'] as String;
    final password = await askNetworkPassword(
      context,
      network: ssid,
      note: failure['uuid'] == null
          ? null
          : 'The new password is saved in NetworkManager for this network.',
    );
    if (password == null) return;
    await controller.set(
      wifiConnectSettingId,
      connectRequest(
        uuid: failure['uuid'] as String?,
        ssid: ssid,
        password: password,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final failure = controller.failure;
    if (failure == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const .only(bottom: 16),
      child: Material(
        color: colors.errorContainer,
        borderRadius: .circular(24),
        child: SettingRow(
          id: 'network-failure',
          label: Text(
            failure['message'] as String,
            style: TextStyle(color: colors.onErrorContainer),
          ),
          control: failure['needs_password'] == true
              ? FilledButton(
                  onPressed: () => _retry(context, failure),
                  child: const Text('Enter password'),
                )
              : null,
        ),
      ),
    );
  }
}

/// The large summary at the top of a network page.
class NetworkHero extends StatelessWidget {
  const NetworkHero({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    this.action,
    this.children = const [],
  });
  final IconData icon;
  final String title;
  final String status;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final heading = Row(
      mainAxisSize: .min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: colors.primary, shape: .circle),
          child: Icon(icon, size: 32, color: colors.onPrimary),
        ),
        const SizedBox(width: 20),
        Flexible(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(
                title,
                style: text.headlineSmall?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                status,
                style: text.bodyMedium?.copyWith(
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    return Material(
      color: colors.primaryContainer,
      borderRadius: .circular(32),
      child: Padding(
        padding: const .all(24),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (action == null)
              heading
            else
              SettingsRowLayout(left: heading, right: action!),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 20),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

/// Labeled facts in equal columns that wrap with the available width.
class NetworkFacts extends StatelessWidget {
  const NetworkFacts(this.facts, {super.key, this.columnWidth = 220});
  final List<(String, String)> facts;
  final double columnWidth;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / columnWidth).floor().clamp(
          1,
          4,
        );
        final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 20,
          children: [
            for (final (label, value) in facts)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(label, style: text.labelMedium),
                    const SizedBox(height: 4),
                    Text(value, style: text.bodyLarge),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  return unit == 0
      ? '$bytes B'
      : '${value.toStringAsFixed(value < 10 ? 1 : 0)} ${units[unit]}';
}

/// How far a link in a [NetworkPath] carries traffic.
enum PathLink { working, degraded, broken }

/// One stop along a [NetworkPath].
typedef PathNode = ({IconData icon, String label, String? detail});

/// Where traffic goes, from this device to its destination, with each hop's state.
class NetworkPath extends StatelessWidget {
  const NetworkPath({super.key, required this.nodes, required this.links})
    : assert(links.length == nodes.length - 1);
  final List<PathNode> nodes;
  final List<PathLink> links;

  String _linkLabel(PathLink link) => switch (link) {
    .working => 'working',
    .degraded => 'limited',
    .broken => 'not connected',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget node(PathNode node) => Column(
      mainAxisSize: .min,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: colors.surfaceContainerLowest,
            shape: .circle,
          ),
          child: Icon(node.icon, color: colors.primary),
        ),
        const SizedBox(height: 8),
        Text(
          node.label,
          style: text.labelLarge,
          textAlign: .center,
          maxLines: 2,
          overflow: .ellipsis,
        ),
        if (node.detail case final detail?)
          Text(
            detail,
            style: text.bodySmall,
            textAlign: .center,
            maxLines: 2,
            overflow: .ellipsis,
          ),
      ],
    );
    Widget link(PathLink link) {
      final (color, icon) = switch (link) {
        .working => (colors.primary, Icons.check_rounded),
        .degraded => (colors.tertiary, Icons.priority_high_rounded),
        .broken => (colors.outlineVariant, Icons.close_rounded),
      };
      return Padding(
        padding: const .only(top: 16),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: .circular(2),
                ),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(color: color, shape: .circle),
              child: Icon(icon, size: 14, color: colors.surface),
            ),
            Expanded(
              child: Container(
                height: 4,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: .circular(2),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: [
        for (var i = 0; i < links.length; i++)
          '${nodes[i].label} to ${nodes[i + 1].label}: ${_linkLabel(links[i])}',
      ].join('. '),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Nodes share the width with links that keep at least a third of it.
            final width = (constraints.maxWidth / (nodes.length * 1.5)).clamp(
              56.0,
              112.0,
            );
            return Row(
              crossAxisAlignment: .start,
              children: [
                for (var i = 0; i < nodes.length; i++) ...[
                  SizedBox(width: width, child: node(nodes[i])),
                  if (i < links.length) Expanded(child: link(links[i])),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Text for a connection's addressing, as a readout beside its Edit button.
String ipSummary(Map ip) => switch (ip['ipv4']) {
  'manual' => [
    'Manual',
    ...(ip['addresses'] as List).cast<String>(),
    if ((ip['gateway'] as String).isNotEmpty) 'Gateway ${ip['gateway']}',
  ].join('\n'),
  'auto' => 'Automatic (DHCP)',
  'shared' => 'Shared to other devices',
  'disabled' => 'IPv4 off',
  final String method => 'Set elsewhere: $method',
  _ => 'Unknown',
};

String dnsSummary(Map ip) {
  final servers = (ip['dns'] as List).cast<String>();
  if (ip['auto_dns'] == true) {
    return servers.isEmpty
        ? 'Automatic (DHCP)'
        : ['Automatic, plus', ...servers].join('\n');
  }
  return ['Manual', ...servers].join('\n');
}
