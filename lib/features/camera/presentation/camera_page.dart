import 'dart:async';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../settings/presentation/settings_widgets.dart';
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
        FilledButton.tonalIcon(
          onPressed: _playing
              ? _stop
              : (controller.available && selected != null ? _start : null),
          icon: Icon(_playing ? Icons.stop_rounded : Icons.videocam_outlined),
          label: Text(_playing ? 'Stop preview' : 'Start preview'),
        ),
        if (_previewError != null)
          Padding(padding: const .only(top: 12), child: Text(_previewError!)),
      ],
    ),
  );
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
              _CameraSlider(
                key: ValueKey('${camera['serial']}-${entry.key}'),
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
            OutlinedButton.icon(
              onPressed: enabled ? () => controller.set(camera, 'reset') : null,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Reset camera settings'),
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
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.reconcile(camera, 'system'),
                      child: const Text('Use system configuration'),
                    ),
                    TextButton(
                      onPressed: controller.busy
                          ? null
                          : () => controller.reconcile(camera, 'settings'),
                      child: const Text('Apply Settings configuration'),
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
                  child: DropdownButtonFormField<String>(
                    initialValue: _selected,
                    key: ValueKey(_selected),
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Camera'),
                    items: [
                      for (final d in controller.devices)
                        DropdownMenuItem(
                          value: d['name'] as String,
                          child: Text(
                            '${d['description']} (${d['name']})',
                            overflow: .ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (name) async {
                      await _stop();
                      if (!mounted) return;
                      setState(() {
                        _selected = name;
                        _serial = selected?['serial'] as int?;
                        _previewError = null;
                      });
                    },
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

class _CameraSlider extends StatefulWidget {
  const _CameraSlider({
    super.key,
    required this.label,
    required this.icon,
    required this.control,
    required this.enabled,
    required this.change,
  });
  final String label;
  final IconData icon;
  final Map control;
  final bool enabled;
  final Future<void> Function(double) change;
  @override
  State<_CameraSlider> createState() => _CameraSliderState();
}

class _CameraSliderState extends State<_CameraSlider> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final min = (widget.control['min'] as num).toDouble(),
        max = (widget.control['max'] as num).toDouble(),
        step = (widget.control['step'] as num).toDouble();
    final value = _drag ?? (widget.control['value'] as num).toDouble();
    return Padding(
      padding: const .only(bottom: 16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(widget.icon),
              const SizedBox(width: 12),
              Expanded(child: Text(widget.label)),
              Text(value.toStringAsFixed(step >= 1 ? 0 : 2)),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: step > 0 && (max - min) / step <= 10000
                ? ((max - min) / step).round()
                : null,
            label: '$value',
            onChanged: widget.enabled ? (v) => setState(() => _drag = v) : null,
            onChangeEnd: widget.enabled
                ? (v) async {
                    setState(() => _drag = v);
                    await widget.change(v);
                    if (mounted) setState(() => _drag = null);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
