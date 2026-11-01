import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/display_backend.dart';

const displayOutputId = 'hypr-monitor-fields.output';
const displayPositionId = 'hypr-monitor-fields.position';
const displayDetectId = 'display.15697afc';
const displayBrightnessId = 'display.5d419889';
const displayColorId = 'display.af8e280d';
const displayHdrId = 'display.0ce92088';
const displayScaleId = 'display.12e2ed4d';
const displayResolutionId = 'display.44f6b9b0';
const displayRefreshId = 'advanced-display.34d8396d';
const displayOrientationId = 'display.9843ad76';
const displayLayoutId = 'display.7cb5dc06';
const displayDesktopModeId = 'advanced-display.3b3ebb60';
const displaySignalModeId = 'advanced-display.761b7ac8';
const displayColorSpaceId = 'advanced-display.3278abf9';
const displayDeviceId = 'advanced-display.device';
const displayBitDepthId = 'advanced-display.91720250';
const displayVrrId = 'advanced-display.2d80c2c4';
const displayEotfId = 'hypr-monitor-fields.sdr-eotf';
const displaySupportsHdrId = 'hypr-monitor-fields.supports-hdr';
const displaySupportsWideId = 'hypr-monitor-fields.supports-wide-color';

/// Free-form advanced fields, mapped to their Hyprland rule field.
const displayTextFields = {
  'hypr-monitor-fields.sdrbrightness': 'sdrbrightness',
  'hypr-monitor-fields.sdrsaturation': 'sdrsaturation',
  'hypr-monitor-fields.sdr-min-luminance': 'sdr_min_luminance',
  'hypr-monitor-fields.sdr-max-luminance': 'sdr_max_luminance',
  'hypr-monitor-fields.min-luminance': 'min_luminance',
  'hypr-monitor-fields.max-luminance': 'max_luminance',
  'hypr-monitor-fields.max-avg-luminance': 'max_avg_luminance',
  'hypr-monitor-fields.icc': 'icc',
  'hypr-monitor-fields.reserved-area': 'reserved_area',
};

const displaySettingIds = {
  displayOutputId,
  displayPositionId,
  displayDetectId,
  displayBrightnessId,
  displayColorId,
  displayHdrId,
  displayScaleId,
  displayResolutionId,
  displayRefreshId,
  displayOrientationId,
  displayLayoutId,
  displayDesktopModeId,
  displaySignalModeId,
  displayColorSpaceId,
  displayDeviceId,
  displayBitDepthId,
  displayVrrId,
  displayEotfId,
  displaySupportsHdrId,
  displaySupportsWideId,
  ...{
    'hypr-monitor-fields.sdrbrightness',
    'hypr-monitor-fields.sdrsaturation',
    'hypr-monitor-fields.sdr-min-luminance',
    'hypr-monitor-fields.sdr-max-luminance',
    'hypr-monitor-fields.min-luminance',
    'hypr-monitor-fields.max-luminance',
    'hypr-monitor-fields.max-avg-luminance',
    'hypr-monitor-fields.icc',
    'hypr-monitor-fields.reserved-area',
  },
};

class DisplayMode {
  const DisplayMode(this.width, this.height, this.refresh);
  final int width;
  final int height;
  final double refresh;
  String get size => '${width}x$height';
}

class DisplayOutput {
  DisplayOutput(Map<String, dynamic> map)
    : name = map['name'] as String,
      description = map['description'] as String,
      make = map['make'] as String,
      model = map['model'] as String,
      serial = map['serial'] as String,
      physicalWidth = map['physical_width'] as int,
      physicalHeight = map['physical_height'] as int,
      width = map['width'] as int,
      height = map['height'] as int,
      refreshRate = (map['refresh_rate'] as num).toDouble(),
      x = map['x'] as int,
      y = map['y'] as int,
      scale = (map['scale'] as num).toDouble(),
      transform = map['transform'] as int,
      disabled = map['disabled'] as bool,
      desktopMode = map['desktop_mode'] as String,
      signalMode = map['signal_mode'] as String,
      colorSpace = map['color_space'] as String,
      modes = [
        for (final mode in map['modes'] as List)
          DisplayMode(
            mode['width'] as int,
            mode['height'] as int,
            (mode['refresh'] as num).toDouble(),
          ),
      ],
      scaleOptions = (map['scale_options'] as List).cast<String>(),
      hdrCapable = map['hdr_capable'] as bool,
      wideGamutCapable = map['wide_gamut_capable'] as bool,
      vrrCapable = map['vrr_capable'] as bool,
      values = (map['values'] as Map).cast<String, String>(),
      saved = (map['saved'] as Map?)?.cast<String, String>(),
      conflictFields = (map['conflict_fields'] as List).cast<String>();

  final String name;
  final String description;
  final String make;
  final String model;
  final String serial;
  final int physicalWidth;
  final int physicalHeight;
  final int width;
  final int height;
  final double refreshRate;
  final int x;
  final int y;
  final double scale;
  final int transform;
  final bool disabled;
  final String desktopMode;
  final String signalMode;
  final String colorSpace;
  final List<DisplayMode> modes;
  final List<String> scaleOptions;
  final bool hdrCapable;
  final bool wideGamutCapable;
  final bool vrrCapable;
  final Map<String, String> values;
  final Map<String, String>? saved;
  final List<String> conflictFields;

  String get mirror => values['mirror'] ?? '';
  bool get inLayout => !disabled && mirror.isEmpty;

  /// The rectangle this output occupies in Hyprland's logical layout.
  Rect get logicalRect {
    final rotated = transform.isOdd;
    final scaleBy = scale <= 0 ? 1 : scale;
    return Rect.fromLTWH(
      x.toDouble(),
      y.toDouble(),
      ((rotated ? height : width) / scaleBy).roundToDouble(),
      ((rotated ? width : height) / scaleBy).roundToDouble(),
    );
  }

  String get label {
    final detail = [make, model].where((part) => part.isNotEmpty).join(' ');
    return detail.isEmpty ? name : '$name · $detail';
  }
}

class DisplayPending {
  const DisplayPending(this.output, this.deadline);
  final String output;
  final DateTime deadline;
}

class DisplayBrightness {
  const DisplayBrightness(this.percent, this.reason);
  final int? percent;
  final String reason;
}

/// Places a dragged output next to its neighbours: edges within [threshold] snap
/// together, and a released output never overlaps another one.
Offset snapDisplayPosition(
  Rect dragged,
  List<Rect> others, {
  double threshold = 48,
}) {
  double snapAxis(
    double start,
    double extent,
    Iterable<(double, double)> axes,
  ) {
    var best = start;
    var distance = threshold;
    for (final (low, high) in axes) {
      for (final target in [low, high, low - extent, high - extent]) {
        final gap = (start - target).abs();
        if (gap < distance) {
          distance = gap;
          best = target;
        }
      }
    }
    return best;
  }

  var x = snapAxis(dragged.left, dragged.width, [
    for (final other in others) (other.left, other.right),
  ]);
  var y = snapAxis(dragged.top, dragged.height, [
    for (final other in others) (other.top, other.bottom),
  ]);
  for (var pass = 0; pass < others.length + 1; pass++) {
    final rect = Rect.fromLTWH(x, y, dragged.width, dragged.height);
    final hit = others.where((other) => other.overlaps(rect)).firstOrNull;
    if (hit == null) break;
    final moves = <Offset>[
      Offset(hit.left - dragged.width, y),
      Offset(hit.right, y),
      Offset(x, hit.top - dragged.height),
      Offset(x, hit.bottom),
    ];
    moves.sort(
      (a, b) =>
          (a - Offset(x, y)).distance.compareTo((b - Offset(x, y)).distance),
    );
    x = moves.first.dx;
    y = moves.first.dy;
  }
  return Offset(x.roundToDouble(), y.roundToDouble());
}

class DisplayController extends ChangeNotifier {
  DisplayController(this.backend);
  final DisplayBackend backend;

  /// Seconds a risky change waits for confirmation before the service restores it.
  static const confirmSeconds = 15;

  List<DisplayOutput> outputs = const [];
  Map<String, DisplayBrightness> brightness = const {};
  DisplayPending? pending;
  String? writeBlocked;
  String? errorMessage;
  String? _selected;
  bool isBusy = false;
  bool _disposed = false;
  (String, String, String)? _failed;

  /// Bumped after a failed change or a new selection, so choice widgets drop the
  /// value the user just picked. Background reloads never bump it: they must not
  /// recreate a control the user is editing.
  int revision = 0;
  int _writes = 0;
  final _brightnessQueue = <String, int>{};
  Future<void>? _brightnessWrite;

  bool get hasConflict => outputs.any((o) => o.conflictFields.isNotEmpty);
  bool get canEdit => writeBlocked == null && pending == null;

  DisplayOutput? get selected =>
      outputs.where((o) => o.name == _selected).firstOrNull ??
      outputs.where((o) => o.inLayout).firstOrNull ??
      outputs.firstOrNull;

  String get conflictSummary => [
    for (final output in outputs)
      if (output.conflictFields.isNotEmpty)
        '${output.name}: ${output.conflictFields.map((field) => '$field is ${_shown(output.values[field])}, saved ${_shown(output.saved?[field])}').join('; ')}',
  ].join('\n');

  String _shown(String? value) =>
      value == null || value.isEmpty ? 'not set' : value;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void select(String name) {
    if (_selected == name) return;
    _selected = name;
    revision++;
    _notify();
  }

  void _accept(Map<String, dynamic> map) {
    outputs = [
      for (final raw in map['outputs'] as List)
        DisplayOutput(raw as Map<String, dynamic>),
    ];
    final waiting = map['pending'] as Map<String, dynamic>?;
    pending = waiting == null
        ? null
        : DisplayPending(
            waiting['output'] as String,
            DateTime.now().add(
              Duration(milliseconds: waiting['remaining_ms'] as int),
            ),
          );
    writeBlocked = map['write_blocked'] as String?;
    errorMessage = map['error'] as String?;
  }

  Future<void> reload() async {
    if (isBusy) return;
    try {
      final before = _writes;
      final map = await backend.read();
      // A change finished meanwhile and already delivered newer values.
      if (before != _writes || isBusy) return;
      _accept(map);
    } catch (error) {
      errorMessage = '$error';
    }
    _notify();
  }

  Future<void> loadBrightness() async {
    try {
      _acceptBrightness(await backend.brightness());
    } catch (error) {
      brightness = const {};
      errorMessage = '$error';
    }
    _notify();
  }

  void _acceptBrightness(Map<String, dynamic> map) {
    brightness = {
      for (final raw in map['outputs'] as List)
        raw['output'] as String: DisplayBrightness(
          raw['percent'] as int?,
          raw['reason'] as String,
        ),
    };
  }

  Future<void> _run(Future<void> Function() action) async {
    _writes++;
    isBusy = true;
    _notify();
    try {
      await action();
    } catch (error) {
      errorMessage = '$error';
      revision++;
    } finally {
      isBusy = false;
      _notify();
    }
  }

  String _request(String output, String value) => jsonEncode({
    'output': output,
    'value': value,
    'confirm_seconds': confirmSeconds,
  });

  /// Applies one setting to [output]. Failures stay visible and can be retried.
  Future<void> change(String id, String output, String value) => _run(() async {
    try {
      _accept(await backend.set(id, _request(output, value)));
      _failed = null;
    } catch (_) {
      _failed = (id, output, value);
      rethrow;
    }
  });

  Future<void> setBrightness(String output, int percent) {
    _brightnessQueue[output] = percent;
    return _brightnessWrite ??= _run(() async {
      while (_brightnessQueue.isNotEmpty) {
        final request = _brightnessQueue.entries.first;
        _brightnessQueue.remove(request.key);
        try {
          _acceptBrightness(
            await backend.set(
              displayBrightnessId,
              jsonEncode({'output': request.key, 'value': '${request.value}'}),
            ),
          );
          errorMessage = null;
          _failed = null;
          _notify();
        } catch (_) {
          _failed = (displayBrightnessId, request.key, '${request.value}');
          _brightnessQueue.clear();
          rethrow;
        }
      }
    }).whenComplete(() => _brightnessWrite = null);
  }

  Future<void> detect() => _run(() async {
    _accept(await backend.set(displayDetectId, 'detect'));
    _acceptBrightness(await backend.brightness());
  });

  Future<void> _resolve(String source) => _run(() async {
    final result = await backend.resolve(source);
    _accept(result['display'] as Map<String, dynamic>);
  });

  Future<void> keep() => _resolve('keep');
  Future<void> revert() => _resolve('revert');
  Future<void> useSystemConfiguration() => _resolve('system');
  Future<void> applySavedConfiguration() => _resolve('settings');

  Future<void> retry() async {
    final failed = _failed;
    if (failed == null) return reload();
    if (failed.$1 == displayBrightnessId) {
      return setBrightness(failed.$2, int.parse(failed.$3));
    }
    return change(failed.$1, failed.$2, failed.$3);
  }

  int get pendingSeconds => pending == null
      ? 0
      : math.max(
          0,
          (pending!.deadline.difference(DateTime.now()).inMilliseconds / 1000)
              .ceil(),
        );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class DisplayScope extends InheritedNotifier<DisplayController> {
  const DisplayScope({
    super.key,
    required DisplayController controller,
    required super.child,
  }) : super(notifier: controller);
  static DisplayController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DisplayScope>()?.notifier;
}
