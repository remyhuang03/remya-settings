import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/remya_client.dart';

import 'network_widgets.dart';

/// The desktop proxy follows live GSettings, which proxy tools change routinely.
class ProxyPage extends StatefulWidget {
  const ProxyPage({super.key, required this.client});
  final SettingsClient client;

  @override
  State<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends State<ProxyPage> {
  Map<String, dynamic>? _value;
  String? _error;
  bool _busy = false;
  Timer? _timer;

  /// Script mode needs its address first, so choosing it only shows the field.
  bool _scriptDraft = false;

  @override
  void initState() {
    super.initState();
    _read();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_busy) _read();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final value = await widget.client.readProxy();
      if (mounted) setState(() => _value = value);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  /// Returns the failure, if any, so a field can keep the rejected text.
  Future<String?> _set(String id, String value) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    try {
      final state = await widget.client.setProxy(id, value);
      if (mounted) setState(() => _value = state);
    } catch (error) {
      failure = '$error';
      await _read();
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = failure;
      });
    }
    return failure;
  }

  String _status(Map value) => switch (value['mode']) {
    'detect' => 'Finds the proxy automatically (WPAD)',
    'script' => 'Uses a setup script',
    'manual' => [
      'Manual',
      for (final key in ['http', 'https', 'socks'])
        if (value[key] case final String server) '${key.toUpperCase()} $server',
    ].join('\n'),
    _ => 'Off: apps connect directly',
  };

  String? get _proxyDetail => switch (_value?['mode']) {
    'manual' => _value?['http'] as String? ?? _value?['socks'] as String?,
    'script' => Uri.tryParse(_value?['script'] as String? ?? '')?.host,
    'detect' => 'Automatic',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (value == null) {
      return _error == null
          ? const RemyaLoadingBar()
          : SettingsErrorCard(message: _error!, onRetry: _read);
    }
    if (value['available'] != true) {
      return SettingsErrorCard(
        message:
            value['error'] as String? ?? 'The desktop proxy is unavailable',
        onRetry: _read,
      );
    }
    final mode = _scriptDraft ? 'script' : value['mode'] as String;
    final direct = mode == 'none';
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (_error case final error?)
          SettingsErrorCard(message: error, onRetry: _busy ? null : _read),
        NetworkHero(
          icon: direct ? Icons.arrow_forward_rounded : Icons.alt_route_rounded,
          title: 'Proxy',
          status: _status(value),
          children: [
            NetworkPath(
              nodes: [
                (icon: Icons.apps_rounded, label: 'Apps', detail: null),
                if (!direct)
                  (
                    icon: Icons.dns_outlined,
                    label: 'Proxy server',
                    detail: _proxyDetail,
                  ),
                (icon: Icons.public_rounded, label: 'Internet', detail: null),
              ],
              links: [if (!direct) PathLink.working, PathLink.working],
            ),
          ],
        ),
        const SettingsSectionTitle('Proxy setup'),
        SettingsSurface(
          padding: .zero,
          child: settingsRows([
            SettingRow(
              id: proxyModeSettingId,
              label: const Text('Use a proxy'),
              control: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'none', label: Text('Off')),
                  ButtonSegment(value: 'detect', label: Text('Detect')),
                  ButtonSegment(value: 'script', label: Text('Script')),
                  ButtonSegment(value: 'manual', label: Text('Manual')),
                ],
                selected: {mode},
                onSelectionChanged: _busy
                    ? null
                    : (selection) {
                        final choice = selection.single;
                        setState(
                          () => _scriptDraft =
                              choice == 'script' &&
                              (value['script'] as String).isEmpty,
                        );
                        if (!_scriptDraft) _set(proxyModeSettingId, choice);
                      },
              ),
            ),
            if (mode == 'script')
              _ProxyField(
                id: proxyScriptSettingId,
                label: 'Script address',
                hint: 'http://wpad.example/proxy.pac',
                helper: _scriptDraft
                    ? 'Save an address to start using the setup script'
                    : null,
                value: value['script'] as String,
                enabled: !_busy,
                onSave: (text) async {
                  final failure = await _set(proxyScriptSettingId, text);
                  if (failure == null && mounted) {
                    setState(() => _scriptDraft = false);
                  }
                  return failure;
                },
              ),
            if (mode == 'manual') ...[
              for (final (id, key, label) in [
                (proxyHttpSettingId, 'http', 'HTTP proxy'),
                (proxyHttpsSettingId, 'https', 'HTTPS proxy'),
                (proxySocksSettingId, 'socks', 'SOCKS host'),
              ])
                _ProxyField(
                  id: id,
                  label: label,
                  hint: '127.0.0.1:8080',
                  helper: 'host:port, or empty for none',
                  value: value[key] as String? ?? '',
                  enabled: !_busy,
                  onSave: (text) => _set(id, text),
                ),
              _IgnoreHosts(
                hosts: (value['ignore'] as List).cast<String>(),
                enabled: !_busy,
                onChanged: (hosts) =>
                    _set(proxyIgnoreSettingId, jsonEncode(hosts)),
              ),
            ],
          ]),
        ),
        Padding(
          padding: const .only(top: 16),
          child: Text(
            'Applies to apps that follow the desktop proxy, such as GTK apps, Chromium and Firefox set to use system proxy settings. Terminal programs read proxy environment variables instead.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// A text value saved on Enter, on the Save button, or when focus leaves it.
class _ProxyField extends StatefulWidget {
  const _ProxyField({
    required this.id,
    required this.label,
    required this.hint,
    required this.value,
    required this.enabled,
    required this.onSave,
    this.helper,
  });
  final String id;
  final String label;
  final String hint;
  final String? helper;
  final String value;
  final bool enabled;
  final Future<String?> Function(String) onSave;

  @override
  State<_ProxyField> createState() => _ProxyFieldState();
}

class _ProxyFieldState extends State<_ProxyField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();
  String? _problem;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _save();
    });
  }

  @override
  void didUpdateWidget(_ProxyField old) {
    super.didUpdateWidget(old);
    // Live changes from other tools replace the text only while it is not being edited.
    if (!_focus.hasFocus && _problem == null && widget.value != _text.text) {
      _text.text = widget.value;
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text == widget.value) {
      if (_problem != null) setState(() => _problem = null);
      return;
    }
    final failure = await widget.onSave(text);
    if (mounted) {
      setState(() => _problem = failure?.replaceFirst(RegExp(r'^.*?: ?'), ''));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey(widget.id),
    padding: const .symmetric(horizontal: 20, vertical: 14),
    child: TextField(
      controller: _text,
      focusNode: _focus,
      enabled: widget.enabled,
      autocorrect: false,
      onSubmitted: (_) => _save(),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        helperText: widget.helper,
        errorText: _problem,
        suffixIcon: IconButton(
          tooltip: 'Save ${widget.label}',
          onPressed: widget.enabled ? _save : null,
          icon: const Icon(Icons.check_rounded),
        ),
      ),
    ),
  );
}

/// Hosts reached directly, edited as chips.
class _IgnoreHosts extends StatefulWidget {
  const _IgnoreHosts({
    required this.hosts,
    required this.enabled,
    required this.onChanged,
  });
  final List<String> hosts;
  final bool enabled;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_IgnoreHosts> createState() => _IgnoreHostsState();
}

class _IgnoreHostsState extends State<_IgnoreHosts> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add() {
    final hosts = _text.text
        .split(RegExp(r'[\s,]+'))
        .where((h) => h.isNotEmpty && !widget.hosts.contains(h))
        .toList();
    if (hosts.isEmpty) return;
    _text.clear();
    widget.onChanged([...widget.hosts, ...hosts]);
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const ValueKey(proxyIgnoreSettingId),
    padding: const .fromLTRB(20, 14, 20, 20),
    child: Column(
      crossAxisAlignment: .start,
      children: [
        Text(
          "Don't use the proxy for",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final host in widget.hosts)
              InputChip(
                label: Text(host),
                onDeleted: widget.enabled
                    ? () => widget.onChanged([
                        for (final h in widget.hosts)
                          if (h != host) h,
                      ])
                    : null,
                deleteButtonTooltipMessage: 'Remove $host',
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          enabled: widget.enabled,
          onSubmitted: (_) => _add(),
          decoration: InputDecoration(
            labelText: 'Add hosts',
            hintText: 'localhost, 10.0.0.0/8, *.example.com',
            suffixIcon: IconButton(
              tooltip: 'Add hosts',
              onPressed: widget.enabled ? _add : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
      ],
    ),
  );
}
