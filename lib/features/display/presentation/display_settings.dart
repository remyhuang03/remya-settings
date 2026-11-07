import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/display_controller.dart';

const _colorPresets = {
  'auto': 'Automatic',
  'srgb': 'sRGB',
  'dcip3': 'DCI-P3',
  'dp3': 'Display P3',
  'adobe': 'Adobe RGB',
  'wide': 'Wide gamut (BT.2020)',
  'edid': 'Display primaries (EDID)',
  'hdr': 'HDR',
  'hdredid': 'HDR with display primaries',
};
const _wideOnlyPresets = {'dcip3', 'dp3', 'adobe', 'wide', 'edid'};
const _hdrPresets = {'hdr', 'hdredid'};
const _rotations = {'0': '0°', '1': '90°', '2': '180°', '3': '270°'};
const _capability = {'0': 'Automatic', '1': 'Force on', '-1': 'Force off'};
const _eotf = {'default': 'Default', 'gamma22': 'Gamma 2.2', 'srgb': 'sRGB'};

String _rate(double hz) {
  final text = hz.toStringAsFixed(2);
  return '${text.replaceFirst(RegExp(r'\.?0+$'), '')} Hz';
}

String _percent(String scale) =>
    '${((double.tryParse(scale) ?? 1) * 100).round()}%';

/// Interactive arrangement of the real outputs.
class DisplayArrangement extends StatefulWidget {
  const DisplayArrangement({super.key, required this.controller});
  final DisplayController controller;
  @override
  State<DisplayArrangement> createState() => _DisplayArrangementState();
}

class _DisplayArrangementState extends State<DisplayArrangement> {
  static const _height = 240.0;
  String? _dragging;
  Rect? _dragRect;

  @override
  void initState() {
    super.initState();
    // Brightness can touch slow I2C buses, so it is read only when this page opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.loadBrightness();
    });
  }

  void _finishDrag(DisplayOutput output, List<Rect> others) {
    final rect = _dragRect;
    setState(() {
      _dragging = null;
      _dragRect = null;
    });
    if (rect == null) return;
    final place = snapDisplayPosition(rect, others);
    final moved = place.dx.toInt() != output.x || place.dy.toInt() != output.y;
    if (moved) {
      widget.controller.change(
        displayPositionId,
        output.name,
        '${place.dx.toInt()}x${place.dy.toInt()}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final text = Theme.of(context).textTheme;
    final active = controller.outputs.where((o) => o.inLayout).toList();
    final idle = controller.outputs.where((o) => !o.inLayout).toList();
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Display arrangement', style: text.titleMedium),
              ),
              IconButton(
                key: const ValueKey('display-refresh'),
                tooltip: 'Refresh displays',
                onPressed: controller.isBusy ? null : controller.detect,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SelectionContainer.disabled(
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _canvas(active, constraints.maxWidth),
            ),
          ),
          if (idle.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final output in idle)
                  ChoiceChip(
                    key: ValueKey('display-idle-${output.name}'),
                    selected: controller.selected?.name == output.name,
                    avatar: Icon(
                      output.disabled
                          ? Icons.desktop_access_disabled_outlined
                          : Icons.content_copy_rounded,
                      size: 18,
                    ),
                    label: Text(
                      output.disabled
                          ? '${output.name} (not in use)'
                          : '${output.name} (mirrors ${output.mirror})',
                    ),
                    onSelected: (_) => controller.select(output.name),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _canvas(List<DisplayOutput> active, double width) {
    final controller = widget.controller;
    final rects = {for (final o in active) o.name: o.logicalRect};
    final bounds = rects.values.fold<Rect?>(
      null,
      (all, rect) => all == null ? rect : all.expandToInclude(rect),
    );
    if (bounds == null) return const SizedBox.shrink();
    const margin = 12.0;
    final factor = [
      (width - margin * 2) / bounds.width,
      (_height - margin * 2) / bounds.height,
    ].reduce((a, b) => a < b ? a : b);
    final origin = Offset(
      (width - bounds.width * factor) / 2,
      (_height - bounds.height * factor) / 2,
    );
    Rect place(Rect rect) => Rect.fromLTWH(
      origin.dx + (rect.left - bounds.left) * factor,
      origin.dy + (rect.top - bounds.top) * factor,
      rect.width * factor,
      rect.height * factor,
    );
    return SizedBox(
      key: const ValueKey('display-arrangement'),
      height: _height,
      child: Stack(
        children: [
          for (final (index, output) in active.indexed)
            Positioned.fromRect(
              rect: place(
                output.name == _dragging
                    ? (_dragRect ?? rects[output.name]!)
                    : rects[output.name]!,
              ),
              child: _DisplayTile(
                output: output,
                number: index + 1,
                selected: controller.selected?.name == output.name,
                onTap: () => controller.select(output.name),
                onPanStart: controller.canEdit && active.length > 1
                    ? () => setState(() {
                        controller.select(output.name);
                        _dragging = output.name;
                        _dragRect = rects[output.name];
                      })
                    : null,
                onPanUpdate: (delta) => setState(() {
                  _dragRect = _dragRect?.shift(delta / factor);
                }),
                onPanEnd: () => _finishDrag(output, [
                  for (final other in active)
                    if (other.name != output.name) rects[other.name]!,
                ]),
              ),
            ),
        ],
      ),
    );
  }
}

class _DisplayTile extends StatefulWidget {
  const _DisplayTile({
    required this.output,
    required this.number,
    required this.selected,
    required this.onTap,
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
  });
  final DisplayOutput output;
  final int number;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onPanStart;
  final ValueChanged<Offset> onPanUpdate;
  final VoidCallback onPanEnd;

  @override
  State<_DisplayTile> createState() => _DisplayTileState();
}

class _DisplayTileState extends State<_DisplayTile> {
  static const _slop = 4.0;
  Offset _travel = .zero;
  bool _dragging = false;

  void _move(PointerMoveEvent event) {
    if (widget.onPanStart == null) return;
    if (!_dragging) {
      _travel += event.delta;
      if (_travel.distance < _slop) return;
      _dragging = true;
      widget.onPanStart!();
      widget.onPanUpdate(_travel);
      return;
    }
    widget.onPanUpdate(event.delta);
  }

  void _up(PointerUpEvent event) {
    if (_dragging) {
      widget.onPanEnd();
    } else if (widget.onPanStart != null) {
      widget.onTap();
    }
    _reset();
  }

  void _reset() {
    _travel = .zero;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final foreground = selected
        ? colors.onPrimaryContainer
        : colors.onSecondaryContainer;
    final tile = Material(
      color: selected ? colors.primaryContainer : colors.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: .circular(16),
        side: BorderSide(
          color: selected ? colors.primary : colors.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Center(
          child: FittedBox(
            fit: .scaleDown,
            child: Padding(
              padding: const .all(8),
              child: Column(
                mainAxisSize: .min,
                children: [
                  Text(
                    '${widget.number}',
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(color: foreground),
                  ),
                  Text(
                    widget.output.name,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Semantics(
      selected: selected,
      label: 'Display ${widget.number}, ${widget.output.label}',
      child: Listener(
        key: ValueKey('display-tile-${widget.output.name}'),
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: (_) => _reset(),
        // Claims the pointer so the page cannot scroll a touch drag away from the tile;
        // keyboard activation still reaches the InkWell.
        child: widget.onPanStart == null
            ? tile
            : RawGestureDetector(
                gestures: {
                  EagerGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        EagerGestureRecognizer
                      >(EagerGestureRecognizer.new, (_) {}),
                },
                child: tile,
              ),
      ),
    );
  }
}

/// One catalog row of the Display page, bound to the selected output.
class DisplaySettingRow extends StatelessWidget {
  const DisplaySettingRow({
    super.key,
    required this.setting,
    required this.controller,
  });
  final SettingSpec setting;
  final DisplayController controller;

  @override
  Widget build(BuildContext context) {
    final output = controller.selected;
    final text = Theme.of(context).textTheme;
    final detail = output == null ? null : _readout(output);
    final hint = output == null ? 'No display detected' : _hint(output);
    final label = Column(
      crossAxisAlignment: .start,
      children: [
        Text(setting.title, style: text.bodyLarge),
        const SizedBox(height: 6),
        Text(setting.reason, style: text.bodySmall),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(
            detail,
            key: ValueKey('display-readout-${setting.id}'),
            style: text.bodyMedium,
          ),
        ],
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(
            hint,
            key: ValueKey('display-hint-${setting.id}'),
            style: text.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    if (setting.kind == .info || output == null) {
      return SettingRow(id: setting.id, label: label);
    }
    return SettingRow(
      id: setting.id,
      label: label,
      control: Semantics(label: setting.title, child: _control(output)),
    );
  }

  String? _readout(DisplayOutput output) => switch (setting.id) {
    displayPositionId when !output.disabled =>
      'Now at ${output.x}, ${output.y}',
    displayResolutionId => '${output.width} × ${output.height}',
    displayDesktopModeId => output.desktopMode,
    displaySignalModeId => output.signalMode,
    displayColorSpaceId => output.colorSpace,
    displayDeviceId => switch ([
      if (output.description.isNotEmpty) output.description,
      if (output.physicalWidth > 0)
        '${output.physicalWidth} × ${output.physicalHeight} mm',
    ]) {
      [] => 'Not reported by this display',
      final parts => parts.join('\n'),
    },
    displayBrightnessId => switch (controller.brightness[output.name]) {
      DisplayBrightness(percent: final int value) => '$value%',
      _ => null,
    },
    _ => null,
  };

  String? _hint(DisplayOutput output) {
    if (setting.id == displayOutputId || setting.id == displayDetectId) {
      return null;
    }
    if (setting.id == displayLayoutId) return null;
    if (setting.kind != .info && output.disabled) {
      return 'This display is not in use.';
    }
    final geometry = {
      displayPositionId,
      displayScaleId,
      displayResolutionId,
      displayRefreshId,
      displayOrientationId,
    };
    if (geometry.contains(setting.id) && output.mirror.isNotEmpty) {
      return 'Follows ${output.mirror} while mirroring.';
    }
    return switch (setting.id) {
      displayBrightnessId => switch (controller.brightness[output.name]) {
        null => 'Reading brightness…',
        DisplayBrightness(percent: null, reason: final reason) => reason,
        _ => null,
      },
      displayHdrId when !output.hdrCapable =>
        'This display does not report HDR support.',
      displayVrrId when !output.vrrCapable =>
        'This display does not report variable refresh rate support.',
      _ => null,
    };
  }

  bool _enabled(DisplayOutput output) {
    if (!controller.canEdit || output.disabled) return false;
    return !const {
          displayPositionId,
          displayScaleId,
          displayResolutionId,
          displayRefreshId,
          displayOrientationId,
        }.contains(setting.id) ||
        output.mirror.isEmpty;
  }

  Widget _choice(
    DisplayOutput output,
    String value,
    Map<String, String> entries, {
    bool? enabled,
  }) => DisplayChoice(
    key: ValueKey(
      'display-choice-${setting.id}-${output.name}-$value-${controller.revision}',
    ),
    id: setting.id,
    value: value,
    entries: entries,
    onChanged: (enabled ?? _enabled(output))
        ? (next) => controller.change(setting.id, output.name, next)
        : null,
  );

  Widget _control(DisplayOutput output) {
    final values = output.values;
    switch (setting.id) {
      case displayOutputId:
        return DisplayChoice(
          key: ValueKey('display-choice-output-${output.name}'),
          id: setting.id,
          value: output.name,
          entries: {for (final o in controller.outputs) o.name: o.label},
          onChanged: controller.select,
        );
      case displayPositionId:
        return _DisplayCoordinates(
          key: ValueKey('display-position-${output.name}'),
          id: setting.id,
          x: output.x,
          y: output.y,
          enabled: _enabled(output),
          onSubmitted: (value) =>
              controller.change(setting.id, output.name, value),
        );
      case displayBrightnessId:
        return _BrightnessSlider(
          key: ValueKey(
            'display-brightness-${output.name}-${controller.revision}',
          ),
          percent: controller.brightness[output.name]?.percent,
          isBusy: controller.isBusy,
          onChanged: output.disabled
              ? null
              : (value) => controller.setBrightness(output.name, value),
        );
      case displayColorId:
        final cm = values['cm'] ?? 'srgb';
        return _choice(output, cm, {
          for (final entry in _colorPresets.entries)
            if (entry.key == cm ||
                (!_hdrPresets.contains(entry.key) &&
                    (!_wideOnlyPresets.contains(entry.key) ||
                        output.wideGamutCapable)) ||
                (_hdrPresets.contains(entry.key) && output.hdrCapable))
              entry.key: entry.value,
        });
      case displayHdrId:
        final on = _hdrPresets.contains(values['cm']);
        return Switch(
          key: ValueKey('display-control-${setting.id}'),
          value: on,
          onChanged: _enabled(output) && output.hdrCapable
              ? (next) => controller.change(setting.id, output.name, '$next')
              : null,
        );
      case displayScaleId:
        final scale = values['scale'] ?? 'auto';
        return _choice(output, scale, {
          'auto': 'Automatic',
          if (scale != 'auto' && !output.scaleOptions.contains(scale))
            scale: _percent(scale),
          for (final option in output.scaleOptions) option: _percent(option),
        });
      case displayResolutionId:
        return _ResolutionControl(
          key: ValueKey(
            'display-resolution-${output.name}-${controller.revision}',
          ),
          output: output,
          enabled: _enabled(output),
          onChanged: (value) =>
              controller.change(setting.id, output.name, value),
        );
      case displayRefreshId:
        final rates = <String, String>{
          for (final mode in output.modes)
            if (mode.width == output.width && mode.height == output.height)
              mode.refresh.toStringAsFixed(2): _rate(mode.refresh),
        };
        final current = output.refreshRate.toStringAsFixed(2);
        rates.putIfAbsent(current, () => _rate(output.refreshRate));
        return _choice(output, current, rates);
      case displayOrientationId:
        return SizedBox(
          width: 232,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              DisplayChoice(
                key: ValueKey(
                  'display-rotation-${output.name}-${output.transform}-${controller.revision}',
                ),
                id: setting.id,
                label: 'Rotation',
                value: '${output.transform % 4}',
                entries: _rotations,
                onChanged: _enabled(output)
                    ? (value) => controller.change(
                        setting.id,
                        output.name,
                        '${int.parse(value) + (output.transform >= 4 ? 4 : 0)}',
                      )
                    : null,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Flip')),
                  Switch(
                    key: const ValueKey('display-flip'),
                    value: output.transform >= 4,
                    onChanged: _enabled(output)
                        ? (flip) => controller.change(
                            setting.id,
                            output.name,
                            '${output.transform % 4 + (flip ? 4 : 0)}',
                          )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        );
      case displayLayoutId:
        final others = controller.outputs.where(
          (o) => o.name != output.name && o.inLayout,
        );
        final current = output.disabled
            ? 'disable'
            : output.mirror.isEmpty
            ? 'extend'
            : 'mirror:${output.mirror}';
        return _choice(output, current, {
          'extend': 'Extend desktop',
          current: output.mirror.isEmpty
              ? (output.disabled ? 'Do not use' : 'Extend desktop')
              : 'Mirror ${output.mirror}',
          for (final other in others)
            'mirror:${other.name}': 'Mirror ${other.name}',
          'disable': 'Do not use',
        }, enabled: controller.canEdit);
      case displayBitDepthId:
        return _choice(output, values['bitdepth'] ?? '8', {
          '8': '8-bit',
          '10': '10-bit',
        });
      case displayVrrId:
        final vrr = values['vrr'] ?? '';
        return _choice(output, vrr, {
          '': 'Use Hyprland default',
          '0': 'Off',
          if (output.vrrCapable || vrr == '1') '1': 'On',
          if (output.vrrCapable || vrr == '2') '2': 'Fullscreen only',
          if (output.vrrCapable || vrr == '3')
            '3': 'Fullscreen games and video',
        });
      case displayEotfId:
        return _choice(output, values['sdr_eotf'] ?? 'default', _eotf);
      case displaySupportsHdrId:
        return _choice(output, values['supports_hdr'] ?? '0', _capability);
      case displaySupportsWideId:
        return _choice(
          output,
          values['supports_wide_color'] ?? '0',
          _capability,
        );
    }
    final field = displayTextFields[setting.id]!;
    return DisplayTextField(
      key: ValueKey('display-text-${setting.id}-${output.name}'),
      id: setting.id,
      value: values[field] ?? '',
      enabled: _enabled(output),
      onSubmitted: (value) => controller.change(setting.id, output.name, value),
    );
  }
}

class _DisplayCoordinates extends StatefulWidget {
  const _DisplayCoordinates({
    super.key,
    required this.id,
    required this.x,
    required this.y,
    required this.enabled,
    required this.onSubmitted,
  });
  final String id;
  final int x;
  final int y;
  final bool enabled;
  final Future<void> Function(String) onSubmitted;

  @override
  State<_DisplayCoordinates> createState() => _DisplayCoordinatesState();
}

class _DisplayCoordinatesState extends State<_DisplayCoordinates> {
  late final _x = TextEditingController(text: '${widget.x}');
  late final _y = TextEditingController(text: '${widget.y}');
  final _focus = FocusNode();
  String? _submitted;

  @override
  void didUpdateWidget(covariant _DisplayCoordinates oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _submitted == null) _readback();
  }

  void _readback() {
    _x.text = '${widget.x}';
    _y.text = '${widget.y}';
  }

  Future<void> _commit() async {
    final value = '${_x.text.trim()}x${_y.text.trim()}';
    if (value == '${widget.x}x${widget.y}' || value == _submitted) return;
    _submitted = value;
    await widget.onSubmitted(value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _submitted != value) return;
      _submitted = null;
      if ('${_x.text.trim()}x${_y.text.trim()}' == value) _readback();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _x.dispose();
    _y.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController text) => Expanded(
    child: TextField(
      key: ValueKey('display-control-${widget.id}-${label.toLowerCase()}'),
      controller: text,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(signed: true),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(borderRadius: .all(.circular(14))),
      ),
      onSubmitted: (_) => _commit(),
    ),
  );

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 232,
    child: Focus(
      focusNode: _focus,
      onFocusChange: (focused) {
        if (!focused && mounted) _commit();
      },
      child: Row(
        children: [_field('X', _x), const SizedBox(width: 12), _field('Y', _y)],
      ),
    ),
  );
}

class _ResolutionControl extends StatefulWidget {
  const _ResolutionControl({
    super.key,
    required this.output,
    required this.enabled,
    required this.onChanged,
  });
  final DisplayOutput output;
  final bool enabled;
  final Future<void> Function(String) onChanged;

  @override
  State<_ResolutionControl> createState() => _ResolutionControlState();
}

class _ResolutionControlState extends State<_ResolutionControl> {
  late bool _custom = widget.output.values['mode'] != 'preferred';

  @override
  void didUpdateWidget(covariant _ResolutionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.output.values['mode'] != widget.output.values['mode']) {
      _custom = widget.output.values['mode'] != 'preferred';
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 232,
    child: Column(
      crossAxisAlignment: .stretch,
      children: [
        DisplayChoice(
          id: displayResolutionId,
          value: _custom ? 'custom' : 'preferred',
          entries: const {'preferred': 'Preferred', 'custom': 'Custom'},
          onChanged: widget.enabled
              ? (value) {
                  setState(() => _custom = value == 'custom');
                  widget.onChanged(
                    _custom
                        ? '${widget.output.width}x${widget.output.height}'
                        : 'preferred',
                  );
                }
              : null,
        ),
        if (_custom) ...[
          const SizedBox(height: 12),
          _DisplayCoordinates(
            id: displayResolutionId,
            x: widget.output.width,
            y: widget.output.height,
            enabled: widget.enabled,
            onSubmitted: widget.onChanged,
          ),
        ],
      ],
    ),
  );
}

class DisplayChoice extends StatelessWidget {
  const DisplayChoice({
    super.key,
    required this.id,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.label,
  });
  final String? label;
  final String id;
  final String value;
  final Map<String, String> entries;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 232,
    child: DropdownButtonFormField<String>(
      key: ValueKey('display-control-$id'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: OutlineInputBorder(borderRadius: .all(.circular(14))),
      ),
      items: [
        for (final entry in entries.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: .ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (next) {
              if (next != null && next != value) onChanged!(next);
            },
    ),
  );
}

/// Commits on Enter or when focus leaves; the service validates the value.
class DisplayTextField extends StatefulWidget {
  const DisplayTextField({
    super.key,
    required this.id,
    required this.value,
    required this.enabled,
    required this.onSubmitted,
  });
  final String id;
  final String value;
  final bool enabled;
  final ValueChanged<String> onSubmitted;
  @override
  State<DisplayTextField> createState() => _DisplayTextFieldState();
}

class _DisplayTextFieldState extends State<DisplayTextField> {
  late final _text = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant DisplayTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focus.hasFocus) {
      _text.text = widget.value;
    }
  }

  void _commit() {
    final value = _text.text.trim();
    if (value != widget.value) widget.onSubmitted(value);
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 232,
    child: TextField(
      key: ValueKey('display-control-${widget.id}'),
      controller: _text,
      focusNode: _focus,
      enabled: widget.enabled,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(borderRadius: .all(.circular(14))),
      ),
      onSubmitted: (_) => _commit(),
    ),
  );
}

class _BrightnessSlider extends StatefulWidget {
  const _BrightnessSlider({
    super.key,
    required this.percent,
    required this.isBusy,
    required this.onChanged,
  });
  final int? percent;
  final bool isBusy;
  final ValueChanged<int>? onChanged;
  @override
  State<_BrightnessSlider> createState() => _BrightnessSliderState();
}

class _BrightnessSliderState extends State<_BrightnessSlider> {
  double? _dragging;

  @override
  void didUpdateWidget(covariant _BrightnessSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isBusy) _dragging = null;
  }

  @override
  Widget build(BuildContext context) {
    final percent = widget.percent;
    return SizedBox(
      width: 232,
      child: Slider(
        key: const ValueKey('display-control-$displayBrightnessId'),
        value: _dragging ?? (percent ?? 0).toDouble(),
        max: 100,
        divisions: 100,
        label: '${(_dragging ?? percent ?? 0).round()}%',
        onChanged: percent == null || widget.onChanged == null
            ? null
            : (value) {
                setState(() => _dragging = value);
                widget.onChanged!(value.round());
              },
      ),
    );
  }
}

/// Shows the keep-or-revert countdown wherever the user is in the app.
class DisplayConfirmation extends StatefulWidget {
  const DisplayConfirmation({
    super.key,
    required this.controller,
    this.navigatorKey,
  });
  final DisplayController controller;
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  State<DisplayConfirmation> createState() => _DisplayConfirmationState();
}

class _DisplayConfirmationState extends State<DisplayConfirmation> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    super.dispose();
  }

  void _sync() {
    if (!mounted || _open || widget.controller.pending == null) return;
    final overlay = widget.navigatorKey?.currentState?.overlay?.context;
    _open = true;
    showDialog<void>(
      context: overlay ?? context,
      barrierDismissible: false,
      builder: (_) => _ConfirmDialog(controller: widget.controller),
    ).whenComplete(() => _open = false);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({required this.controller});
  final DisplayController controller;
  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_closeWhenSettled);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_closeWhenSettled);
    super.dispose();
  }

  void _closeWhenSettled() {
    if (mounted && widget.controller.pending == null) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.controller.pendingSeconds;
    return AlertDialog(
      icon: const Icon(Icons.desktop_windows_outlined),
      title: const Text('Keep these display settings?'),
      content: Semantics(
        liveRegion: true,
        child: Text(
          'Your previous settings return in $seconds ${seconds == 1 ? 'second' : 'seconds'}.',
          key: const ValueKey('display-confirm-countdown'),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('display-confirm-revert'),
          onPressed: widget.controller.isBusy ? null : widget.controller.revert,
          child: const Text('Revert'),
        ),
        FilledButton(
          key: const ValueKey('display-confirm-keep'),
          onPressed: widget.controller.isBusy ? null : widget.controller.keep,
          child: const Text('Keep changes'),
        ),
      ],
    );
  }
}
