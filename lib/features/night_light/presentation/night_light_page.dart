import 'package:material_ui/material_ui.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/night_light_controller.dart';

class NightLightPage extends StatefulWidget {
  const NightLightPage({
    super.key,
    required this.page,
    required this.controller,
    this.hdrActive = false,
  });
  final SettingsPageSpec page;
  final NightLightController controller;
  final bool hdrActive;

  @override
  State<NightLightPage> createState() => _NightLightPageState();
}

class _NightLightPageState extends State<NightLightPage> {
  double? _dragging;

  NightLightController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.reload();
  }

  SettingSpec _setting(String id) =>
      widget.page.controls.firstWhere((setting) => setting.id == id);

  Future<void> _pickTime(String id, String current) async {
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: parts.length == 2
          ? TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]))
          : TimeOfDay.now(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hour = '${picked.hour}'.padLeft(2, '0');
    final minute = '${picked.minute}'.padLeft(2, '0');
    await _controller.set(id, '$hour:$minute');
  }

  Widget _toggle(String id, bool value, {required bool enabled}) => Switch(
    key: ValueKey('$id-switch'),
    value: value,
    onChanged: enabled ? (next) => _controller.set(id, '$next') : null,
  );

  Widget _time(String id, String value, {required bool enabled}) =>
      OutlinedButton(
        key: ValueKey('$id-button'),
        onPressed: enabled ? () => _pickTime(id, value) : null,
        child: Text(value),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final enabled = _controller.canChange;
      final kelvin = _dragging ?? _controller.temperature.toDouble();
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            widget.page.description,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          if (_controller.isLoaded && !_controller.isRunning)
            const _Notice(
              'hyprsunset is not running. Changing a setting starts it.',
            ),
          if (widget.hdrActive)
            const _Notice(
              'A display is using HDR. Night light colors may look too strong there.',
            ),
          SettingsSurface(
            padding: .zero,
            child: Column(
              children: [
                _Row(
                  setting: _setting(nightLightEnabledId),
                  subtitle: _controller.hasSchedule
                      ? 'Applies until the next scheduled change.'
                      : null,
                  control: _toggle(
                    nightLightEnabledId,
                    _controller.isEnabled,
                    enabled: enabled,
                  ),
                ),
                const Divider(height: 1, indent: 20, endIndent: 20),
                _Row(
                  setting: _setting(nightLightTemperatureId),
                  subtitle: '${kelvin.round()} K',
                  control: SizedBox(
                    width: 220,
                    child: Slider(
                      key: const ValueKey('night-light-temperature'),
                      value: kelvin.clamp(1000, 6500),
                      min: 1000,
                      max: 6500,
                      divisions: 55,
                      label: '${kelvin.round()} K',
                      onChanged: enabled
                          ? (next) => setState(() => _dragging = next)
                          : null,
                      // Each change restarts hyprsunset, so only the release applies.
                      onChangeEnd: enabled
                          ? (next) {
                              setState(() => _dragging = null);
                              _controller.set(
                                nightLightTemperatureId,
                                '${next.round()}',
                              );
                            }
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SettingsSurface(
            padding: .zero,
            child: Column(
              children: [
                _Row(
                  setting: _setting(nightLightScheduleId),
                  control: _toggle(
                    nightLightScheduleId,
                    _controller.hasSchedule,
                    enabled: enabled,
                  ),
                ),
                const Divider(height: 1, indent: 20, endIndent: 20),
                SettingControlTile(_setting(nightLightTimingId)),
                if (_controller.hasSchedule) ...[
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  _Row(
                    setting: _setting(nightLightStartId),
                    control: _time(
                      nightLightStartId,
                      _controller.start,
                      enabled: enabled,
                    ),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  _Row(
                    setting: _setting(nightLightEndId),
                    control: _time(
                      nightLightEndId,
                      _controller.end,
                      enabled: enabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      );
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.setting, required this.control, this.subtitle});
  final SettingSpec setting;
  final Widget control;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SettingRow(
    id: setting.id,
    label: Column(
      crossAxisAlignment: .start,
      children: [
        Text(setting.title, style: Theme.of(context).textTheme.titleSmall),
        if (subtitle case final subtitle?)
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
    control: control,
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const .only(bottom: 12),
      child: Material(
        color: colors.tertiaryContainer,
        borderRadius: .circular(16),
        child: Padding(
          padding: const .all(14),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colors.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
