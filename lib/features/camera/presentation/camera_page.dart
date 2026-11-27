import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../application/camera_controller.dart';
import '../data/camera_preview.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.controller, this.preview});
  final CameraController controller;
  final CameraPreview? preview;
  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  late final _preview = widget.preview ?? RustCameraPreview();
  Timer? _timer;
  String? _selected;
  int? _serial;
  ui.Image? _image;
  String? _previewError;
  bool _playing = false;
  // Slider readouts while dragging or waiting for readback, by control key.
  final _readouts = <String, double>{};
  int _generation = 0;
  CameraController get controller => widget.controller;
  Map? get selected =>
      controller.devices.where((d) => d['name'] == _selected).firstOrNull;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller.addListener(_changed);
    controller.reload();
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => controller.reload(),
    );
  }

  void _changed() {
    final camera = selected;
    if (camera == null ||
        camera['serial'] != _serial ||
        !controller.available) {
      _stop();
    }
    if (camera == null && controller.devices.isNotEmpty) {
      final first =
          controller.devices
              .where((d) => (d['controls'] as Map).isNotEmpty)
              .firstOrNull ??
          controller.devices.first;
      _selected = first['name'] as String;
      _serial = first['serial'] as int;
    }
    if (mounted) setState(() {});
  }

  Future<void> _stop() async {
    _generation++;
    _playing = false;
    _image?.dispose();
    _image = null;
    try {
      await _preview.stop();
    } catch (e) {
      _previewError = '$e';
    }
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final camera = selected;
    if (camera == null || _playing) return;
    final generation = ++_generation;
    setState(() {
      _playing = true;
      _previewError = null;
    });
    try {
      await _preview.start(camera['name'] as String, camera['serial'] as int);
      if (!mounted || generation != _generation) {
        return;
      }
      while (mounted && generation == _generation && _playing) {
        final frame = await _preview.frame();
        if (!mounted || generation != _generation) {
          frame.dispose();
          break;
        }
        final old = _image;
        setState(() => _image = frame);
        old?.dispose();
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        _previewError = '$e';
        await _stop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != .resumed) unawaited(_stop());
  }

  @override
  void dispose() {
    _timer?.cancel();
    controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _playing = false;
    _image?.dispose();
    unawaited(_preview.stop());
    super.dispose();
  }

  Widget _viewer() => SettingsSurface(
    child: Column(
      children: [
        AspectRatio(
          aspectRatio: 4 / 3,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: .circular(16),
            ),
            child: _image == null
                ? Center(
                    child: _playing
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.videocam_off_outlined, size: 64),
                  )
                : RawImage(image: _image, fit: .contain),
          ),
        ),
        const SizedBox(height: 12),
        SettingsButton(
          onPressed: _playing
              ? _stop
              : (controller.available && selected != null ? _start : null),
          icon: Icon(_playing ? Icons.stop_rounded : Icons.videocam_outlined),
          label: _playing ? 'Stop preview' : 'Start preview',
        ),
        if (_previewError != null)
          Padding(padding: const .only(top: 12), child: Text(_previewError!)),
      ],
    ),
  );
  Widget _slider({
    required String key,
    required String label,
    required IconData icon,
    required Map control,
    required bool enabled,
    required Future<void> Function(double) change,
  }) {
    final min = (control['min'] as num).toDouble(),
        max = (control['max'] as num).toDouble(),
        step = (control['step'] as num).toDouble();
    final value = (control['value'] as num).toDouble();
    String format(double v) => v.toStringAsFixed(step >= 1 ? 0 : 2);
    return Padding(
      key: ValueKey(key),
      padding: const .only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
              Text(format(_readouts[key] ?? value)),
            ],
          ),
          SettingsSlider(
            value: value,
            min: min,
            max: max,
            divisions: step > 0 && (max - min) / step <= 10000
                ? ((max - min) / step).round()
                : null,
            label: format,
            onPreview: (v) => setState(
              () => v == null ? _readouts.remove(key) : _readouts[key] = v,
            ),
            onChanged: enabled
                ? (v) async {
                    // Keep the readout on the released value until it reads back.
                    setState(() => _readouts[key] = v);
                    await change(v);
                    if (mounted) setState(() => _readouts.remove(key));
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _controls(Map camera) {
    final controls = camera['controls'] as Map;
    final enabled =
        controller.available &&
        !controller.busy &&
        !controller.conflicted(camera['name'] as String);
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          for (final entry in const {
            'brightness': ('Brightness', Icons.brightness_6_outlined),
            'contrast': ('Contrast', Icons.contrast_rounded),
            'saturation': ('Saturation', Icons.palette_outlined),
            'sharpness': ('Sharpness', Icons.details_outlined),
          }.entries)
            if (controls[entry.key] case final Map control)
              _slider(
                key: '${camera['serial']}-${entry.key}',
                label: entry.value.$1,
                icon: entry.value.$2,
                control: control,
                enabled: enabled && control['writable'] == true,
                change: (value) =>
                    controller.set(camera, entry.key, value: value),
              ),
          if (controls.isEmpty)
            const Text('This camera has no supported image adjustments.'),
          if (controls.values.any((c) => (c as Map)['writable'] == true))
            SettingsButton(
              onPressed: enabled ? () => controller.set(camera, 'reset') : null,
              icon: const Icon(Icons.restore_rounded),
              label: 'Reset camera settings',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final camera = selected;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (controller.error != null)
          SettingsSurface(
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded),
                const SizedBox(width: 12),
                Expanded(child: Text(controller.error!)),
                IconButton(
                  onPressed: controller.reload,
                  tooltip: 'Retry',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        if (camera != null && controller.conflicted(camera['name'] as String))
          SettingsSurface(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Camera settings differ from the saved configuration.',
                      ),
                    ),
                  ],
                ),
                Text(
                  'System: ${(camera['controls'] as Map).map((k, v) => MapEntry(k, (v as Map)['value']))}\nSettings: ${(controller.state['saved'] as Map? ?? {})[camera['name']]}',
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    SettingsButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.reconcile(camera, 'system'),
                      label: 'Use system configuration',
                    ),
                    SettingsButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.reconcile(camera, 'settings'),
                      label: 'Apply Settings configuration',
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (controller.devices.isEmpty)
          SettingsSurface(
            child: Text(
              controller.available
                  ? 'No cameras found. Connect a camera to use these settings.'
                  : 'Camera service unavailable. Start PipeWire and WirePlumber.',
            ),
          ),
        if (camera != null) ...[
          SettingsSurface(
            child: Row(
              children: [
                const Icon(Icons.camera_alt_outlined),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    spacing: 6,
                    children: [
                      Text(
                        'Camera',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      SettingsDropdown<String>(
                        key: ValueKey(_selected),
                        label: 'Camera',
                        fillWidth: true,
                        selected: _selected,
                        choices: {
                          for (final d in controller.devices)
                            d['name'] as String:
                                '${d['description']} (${d['name']})',
                        },
                        onSelected: (name) async {
                          await _stop();
                          if (!mounted) return;
                          setState(() {
                            _selected = name;
                            _serial = selected?['serial'] as int?;
                            _previewError = null;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) => constraints.maxWidth >= 600
                ? Row(
                    crossAxisAlignment: .start,
                    children: [
                      Expanded(flex: 3, child: _viewer()),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: _controls(camera)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: .stretch,
                    children: [
                      _viewer(),
                      const SizedBox(height: 16),
                      _controls(camera),
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}
