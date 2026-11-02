import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/remya_settings_client.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/network_controller.dart';
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
    final profiles = _controller.profiles
        .where((p) => (p['name'] as String).toLowerCase().contains(query))
        .toList();
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        NetworkFailureBanner(controller: _controller),
        Text(
          widget.page.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        SettingsSurface(
          padding: .zero,
          child: networkRows([
            SettingRow(
              id: knownNetworkAddSettingId,
              label: const Text('Add a network, including a hidden one'),
              control: FilledButton(
                onPressed:
                    _controller.isBusy ||
                        !_controller.allowed('settings.modify.system')
                    ? null
                    : _add,
                child: const Text('Add network'),
              ),
            ),
            Padding(
              padding: const .all(16),
              child: TextField(
                key: const ValueKey('known-networks.search'),
                decoration: const InputDecoration(
                  labelText: 'Search networks',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
          ]),
        ),
        NetworkSectionTitle('${profiles.length} saved networks'),
        if (profiles.isNotEmpty)
          SettingsSurface(
            padding: .zero,
            child: Column(
              children: [
                for (final profile in profiles)
                  _ProfileTile(
                    key: PageStorageKey('known-${profile['uuid']}'),
                    profile: profile,
                    controller: _controller,
                    page: widget.page,
                  ),
              ],
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
          FilledButton(
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Forget'),
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
    networkRows([
      _LastConnected(profile: profile, controller: controller),
      if (!active && controller.wifiEnabled)
        SettingRow(
          id: wifiConnectSettingId,
          label: Text(
            profile['hidden'] == true
                ? 'Connect to this hidden network'
                : 'Connect to this network',
          ),
          control: FilledButton(
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
            child: const Text('Connect'),
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
        control: DropdownMenu<String>(
          key: ValueKey('metered-${profile['metered']}'),
          initialSelection: profile['metered'] as String,
          enabled: _editable,
          onSelected: (value) {
            if (value != null && value != profile['metered']) {
              _setValue(knownNetworkMeteredSettingId, value);
            }
          },
          dropdownMenuEntries: const [
            DropdownMenuEntry(value: 'automatic', label: 'Automatic'),
            DropdownMenuEntry(value: 'yes', label: 'Metered'),
            DropdownMenuEntry(value: 'no', label: 'Not metered'),
          ],
        ),
      ),
      SettingControlTile(
        page.controls.firstWhere((c) => c.id == 'known-networks.mac'),
      ),
      if (personalSecurity(security))
        SettingRow(
          id: knownNetworkPasswordSettingId,
          label: const Text('Password'),
          control: FilledButton.tonal(
            onPressed: _editable ? () => _changePassword(context) : null,
            child: const Text('Change'),
          ),
        ),
      SettingRow(
        id: knownNetworkForgetSettingId,
        label: const Text('Forget this network'),
        control: FilledButton.tonal(
          style: destructiveTonalButtonStyle(context),
          onPressed:
              controller.isBusy ||
                  profile['read_only'] == true ||
                  !controller.allowed('settings.modify.system')
              ? null
              : () => _forget(context),
          child: const Text('Forget'),
        ),
      ),
    ]),
    Padding(
      padding: const .fromLTRB(16, 0, 16, 16),
      child: AdvancedSection(
        storageKey: PageStorageKey('known-advanced-$_uuid'),
        child: SettingControlTile(
          page.controls.firstWhere((c) => c.id == 'known-networks.priority'),
        ),
      ),
    ),
  ];
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
            DropdownMenu<String>(
              initialSelection: _security,
              label: const Text('Security type'),
              expandedInsets: .zero,
              onSelected: (value) {
                if (value != null) setState(() => _security = value);
              },
              dropdownMenuEntries: const [
                DropdownMenuEntry(value: 'open', label: 'Open'),
                DropdownMenuEntry(value: 'wpa2', label: 'WPA2/WPA3 Personal'),
                DropdownMenuEntry(value: 'wpa3', label: 'WPA3 Personal'),
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
