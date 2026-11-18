import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/remya_client.dart';

import '../../settings/domain/settings_catalog.dart';
import '../application/network_controller.dart';
import 'ip_settings.dart';
import 'network_widgets.dart';

class KnownNetworksPage extends StatefulWidget {
  const KnownNetworksPage({
    super.key,
    required this.controller,
    required this.page,
  });
  final NetworkController controller;
  final SettingsPageSpec page;

  @override
  State<KnownNetworksPage> createState() => _KnownNetworksPageState();
}

class _KnownNetworksPageState extends State<KnownNetworksPage> {
  String _query = '';
  NetworkController get _controller => widget.controller;

  Future<void> _add() async {
    final request = await showDialog<Map<String, Object>>(
      context: context,
      builder: (_) => const _AddNetworkDialog(),
    );
    if (request != null) {
      await _controller.set(knownNetworkAddSettingId, jsonEncode(request));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isAvailable) {
      return NetworkUnavailable(controller: _controller);
    }
    final query = _query.toLowerCase();
    final profiles = _controller.wifiProfiles
        .where((p) => (p['name'] as String).toLowerCase().contains(query))
        .toList();
    final indices = {
      for (var i = 0; i < profiles.length; i++)
        PageStorageKey('known-${profiles[i]['uuid']}'): i,
    };
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        NetworkFailureBanner(controller: _controller),
        Text(
          widget.page.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        SettingsList(
          title: '${profiles.length} saved networks',
          actions: [
            SizedBox(
              width: 232,
              child: TextField(
                key: const ValueKey('known-networks.search'),
                decoration: const InputDecoration(
                  labelText: 'Search networks',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            FilledButton.icon(
              key: const ValueKey(knownNetworkAddSettingId),
              onPressed:
                  _controller.isBusy ||
                      !_controller.allowed('settings.modify.system')
                  ? null
                  : _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add network'),
            ),
          ],
          empty: const Text('No saved networks found'),
          itemCount: profiles.length,
          findChildIndexCallback: (key) => indices[key],
          itemBuilder: (context, index) => _ProfileTile(
            key: PageStorageKey('known-${profiles[index]['uuid']}'),
            profile: profiles[index],
            controller: _controller,
            page: widget.page,
          ),
        ),
      ],
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    super.key,
    required this.profile,
    required this.controller,
    required this.page,
  });
  final Map profile;
  final NetworkController controller;
  final SettingsPageSpec page;

  String get _uuid => profile['uuid'] as String;
  bool get _editable =>
      controller.canChangePreferences &&
      profile['read_only'] != true &&
      controller.allowed('settings.modify.system');

  void _setValue(String id, Object value) =>
      controller.set(id, jsonEncode({'uuid': _uuid, 'value': value}));

  Future<void> _changePassword(BuildContext context) async {
    final password = await askNetworkPassword(
      context,
      network: profile['name'] as String,
      note: 'The new password is saved in NetworkManager for this network.',
    );
    if (password != null) _setValue(knownNetworkPasswordSettingId, password);
  }

  Future<void> _forget(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Forget ${profile['name']}?'),
        content: const Text(
          'The saved password and preferences are removed from this device.',
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
            label: const Text('Forget'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.set(knownNetworkForgetSettingId, _uuid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = profile['security'] as String;
    final active = profile['active'] == true;
    return ExpansionTile(
      title: Text(profile['name'] as String),
      subtitle: Text(
        [securityLabel(security), if (active) 'Connected'].join('\n'),
      ),
      children: [
        // Expansion state and nested text scroll positions need separate slots.
        KeyedSubtree(
          key: PageStorageKey('known-body-$_uuid'),
          child: Column(children: _rows(context, security, active)),
        ),
      ],
    );
  }

  List<Widget> _rows(BuildContext context, String security, bool active) => [
    settingsRows([
      _LastConnected(profile: profile, controller: controller),
      if (!active && controller.wifiEnabled)
        SettingRow(
          id: wifiConnectSettingId,
          label: Text(
            profile['hidden'] == true
                ? 'Connect to this hidden network'
                : 'Connect to this network',
          ),
          control: FilledButton.icon(
            onPressed:
                controller.isBusy ||
                    controller.connecting != null ||
                    !controller.allowed('network-control')
                ? null
                : () => controller.set(
                    wifiConnectSettingId,
                    connectRequest(
                      uuid: _uuid,
                      ssid: profile['ssid'] as String,
                    ),
                  ),
            icon: const Icon(Icons.wifi_rounded),
            label: const Text('Connect'),
          ),
        ),
      if (profile['read_only'] == true)
        const NetworkInfoRow(
          id: 'known-networks.read-only',
          label: 'Read-only',
          value: 'This saved network cannot be changed here',
        ),
      SettingRow(
        id: knownNetworkAutoconnectSettingId,
        label: const Text('Connect automatically'),
        control: Switch(
          value: profile['autoconnect'] == true,
          onChanged: _editable
              ? (value) => _setValue(knownNetworkAutoconnectSettingId, value)
              : null,
        ),
      ),
      SettingRow(
        id: knownNetworkMeteredSettingId,
        label: const Text('Metered connection'),
        control: SettingsChoice<String>(
          key: ValueKey('metered-${profile['metered']}'),
          label: 'Metered connection',
          selected: profile['metered'] as String,
          choices: const {
            'automatic': 'Automatic',
            'yes': 'Metered',
            'no': 'Not metered',
          },
          onSelected: _editable
              ? (value) {
                  if (value != profile['metered']) {
                    _setValue(knownNetworkMeteredSettingId, value);
                  }
                }
              : null,
        ),
      ),
      if (!controller.wifiBackendIwd)
        SettingRow(
          id: knownNetworkMacSettingId,
          label: Column(
            crossAxisAlignment: .start,
            children: [
              Text(
                'Random hardware address',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Makes this device harder to track. Takes effect the next time it connects.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          control: SettingsDropdown<String>(
            key: ValueKey('mac-${profile['mac']}'),
            label: 'Random hardware address',
            width: 232,
            selected: profile['mac'] as String,
            choices: {
              '': 'System default',
              'permanent': 'Off',
              'stable': 'On, fixed for this network',
              'random': 'On, new each connection',
              if (!const {
                '',
                'permanent',
                'stable',
                'random',
              }.contains(profile['mac']))
                profile['mac'] as String: 'Set elsewhere: ${profile['mac']}',
            },
            onSelected: _editable
                ? (value) {
                    if (value != profile['mac']) {
                      controller.edit(knownNetworkMacSettingId, _uuid, value);
                    }
                  }
                : null,
          ),
        ),
      ...addressRows(
        context: context,
        controller: controller,
        profile: profile,
        ipId: knownNetworkIpSettingId,
        dnsId: knownNetworkDnsSettingId,
        editable: _editable,
      ),
      if (personalSecurity(security))
        SettingRow(
          id: knownNetworkPasswordSettingId,
          label: const Text('Password'),
          control: FilledButton.tonalIcon(
            onPressed: _editable ? () => _changePassword(context) : null,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Change'),
          ),
        ),
      SettingRow(
        id: knownNetworkForgetSettingId,
        label: const Text('Forget this network'),
        control: FilledButton.tonalIcon(
          style: destructiveTonalButtonStyle(context),
          onPressed:
              controller.isBusy ||
                  profile['read_only'] == true ||
                  !controller.allowed('settings.modify.system')
              ? null
              : () => _forget(context),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Forget'),
        ),
      ),
    ]),
    // iwd chooses among saved networks itself and ignores priorities.
    if (!controller.wifiBackendIwd)
      Padding(
        padding: const .fromLTRB(16, 0, 16, 16),
        child: AdvancedSection(
          storageKey: PageStorageKey('known-advanced-$_uuid'),
          child: _PriorityRow(
            profile: profile,
            enabled: _editable,
            onChanged: (value) =>
                controller.edit(knownNetworkPrioritySettingId, _uuid, value),
          ),
        ),
      ),
  ];
}

/// Higher-priority networks are joined first when several saved ones are in range.
class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    required this.profile,
    required this.enabled,
    required this.onChanged,
  });
  final Map profile;
  final bool enabled;
  final ValueChanged<int> onChanged;

  static const _levels = {-10: 'Low', 0: 'Normal', 10: 'High'};

  @override
  Widget build(BuildContext context) {
    final priority = profile['priority'] as int;
    return SettingRow(
      id: knownNetworkPrioritySettingId,
      label: Column(
        crossAxisAlignment: .start,
        children: [
          Text(
            'Connection priority',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 4),
          Text(
            _levels.containsKey(priority)
                ? 'Preferred over lower-priority networks in range'
                : 'Set elsewhere: $priority. Choose a level to replace it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      control: SettingsSegmentedButton<int>.choices(
        choices: _levels,
        selected: _levels.containsKey(priority) ? priority : null,
        onSelected: enabled ? onChanged : null,
      ),
    );
  }
}

/// Formats through the service so the date follows the system LC_TIME.
class _LastConnected extends StatelessWidget {
  const _LastConnected({required this.profile, required this.controller});
  final Map profile;
  final NetworkController controller;

  Future<String> _text() async {
    final seconds = profile['last_connected'] as int;
    if (seconds == 0) return 'Never';
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int value) => value.toString().padLeft(2, '0');
    return controller.formatDate(
      '${date.year}-${two(date.month)}-${two(date.day)}',
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _text(),
    builder: (context, snapshot) => NetworkInfoRow(
      id: 'known-networks.last-connected',
      label: 'Last connected',
      value: snapshot.data ?? (snapshot.hasError ? 'Unknown' : ''),
    ),
  );
}

class _AddNetworkDialog extends StatefulWidget {
  const _AddNetworkDialog();

  @override
  State<_AddNetworkDialog> createState() => _AddNetworkDialogState();
}

class _AddNetworkDialogState extends State<_AddNetworkDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  String _security = 'wpa2';
  bool _hidden = false;
  bool _autoconnect = true;
  String? _nameProblem;
  String? _passwordProblem;

  bool get _needsPassword => _security != 'open';

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
      _passwordProblem = _needsPassword
          ? passwordProblem(_password.text)
          : null;
    });
    if (_nameProblem != null || _passwordProblem != null) return;
    Navigator.pop(context, <String, Object>{
      'ssid': _name.text,
      'security': _security,
      if (_needsPassword) 'password': _password.text,
      'hidden': _hidden,
      'autoconnect': _autoconnect,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add network'),
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
            Column(
              crossAxisAlignment: .start,
              spacing: 6,
              children: [
                Text(
                  'Security type',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SettingsDropdown<String>(
                  label: 'Security type',
                  fillWidth: true,
                  selected: _security,
                  choices: const {
                    'open': 'Open',
                    'wpa2': 'WPA2/WPA3 Personal',
                    'wpa3': 'WPA3 Personal',
                  },
                  onSelected: (value) => setState(() => _security = value),
                ),
              ],
            ),
            if (_needsPassword) ...[
              const SizedBox(height: 16),
              NetworkPasswordField(
                controller: _password,
                errorText: _passwordProblem,
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: .zero,
              title: const Text('Hidden network'),
              value: _hidden,
              onChanged: (value) => setState(() => _hidden = value),
            ),
            SwitchListTile(
              contentPadding: .zero,
              title: const Text('Connect automatically'),
              value: _autoconnect,
              onChanged: (value) => setState(() => _autoconnect = value),
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
      FilledButton(onPressed: _submit, child: const Text('Add')),
    ],
  );
}
