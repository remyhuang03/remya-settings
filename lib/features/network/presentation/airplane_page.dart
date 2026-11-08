import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/presentation/settings_widgets.dart';

class AirplanePage extends StatefulWidget {
  const AirplanePage({super.key, required this.client});
  final SettingsClient client;

  @override
  State<AirplanePage> createState() => _AirplanePageState();
}

class _AirplanePageState extends State<AirplanePage> {
  Map<String, dynamic>? _value;
  String? _error;
  bool _busy = false;
  Future<void>? _reading;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _reload();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_busy) _reload();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() =>
      _reading ??= _read().whenComplete(() => _reading = null);

  Future<void> _read() async {
    try {
      final value = await widget.client.readAirplane();
      if (mounted) setState(() => _value = value);
    } catch (error) {
      if (mounted) {
        setState(() {
          _value = null;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _set(String id, bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _reading;
      await widget.client.call('Set', [id, '$enabled']);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
    await _reload();
    if (mounted) setState(() => _busy = false);
  }

  Widget _toggle(String id, String title, String detail, bool value) =>
      SettingRow(
        id: id,
        label: Column(
          crossAxisAlignment: .start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        control: Switch(
          key: ValueKey('$id-switch'),
          value: value,
          onChanged: _busy || _value == null
              ? null
              : (value) => _set(id, value),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      if (_error != null) ...[
        Row(
          children: [
            const Icon(Icons.error_outline_rounded),
            const SizedBox(width: 12),
            Expanded(child: Text(_error!)),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: .centerLeft,
          child: TextButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _error = null);
                    await _reload();
                  },
            child: const Text('Refresh'),
          ),
        ),
      ],
      if (_value == null && _error == null) const LinearProgressIndicator(),
      SettingsSurface(
        child: Column(
          children: [
            _toggle(
              airplaneEnabledSettingId,
              'Airplane mode',
              'Turn off Wi-Fi, mobile broadband and all Bluetooth adapters. Turning this off enables these radios.',
              _value?['enabled'] == true,
            ),
            if (_value != null)
              _toggle(
                airplaneWifiSettingId,
                'Wi-Fi',
                'Independent wireless radio control',
                _value?['wifi_enabled'] == true,
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const Text(
        'Radio states follow the system and are never restored at startup. Ethernet stays connected.',
      ),
    ],
  );
}
