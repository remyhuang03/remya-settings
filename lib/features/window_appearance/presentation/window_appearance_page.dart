import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/color_button.dart';
import '../../settings/presentation/settings_widgets.dart';

const _offsetId = 'window-appearance.shadow-offset';

/// Corners, borders, transparency, dimming, shadow and glow of every window.
class WindowAppearancePage extends StatefulWidget {
  const WindowAppearancePage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<WindowAppearancePage> createState() => _WindowAppearancePageState();
}

class _WindowAppearancePageState extends State<WindowAppearancePage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: 'desktop',
  )..reload();
  final _dragging = <String, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The value shown while a slider is held, otherwise the saved one.
  double _number(String id, double fallback) =>
      _dragging[id] ?? (_controller.option(id) as num?)?.toDouble() ?? fallback;

  bool _on(String id) => _controller.option(id) == true;

  Color? _color(String id) =>
      ColorButton.parse(_controller.option(id) as String?);

  (double, double) get _offset {
    final saved = _controller.option(_offsetId);
    final pair = saved is List && saved.length == 2 ? saved : const [0, 0];
    return (
      _dragging['$_offsetId.x'] ?? (pair[0] as num).toDouble(),
      _dragging['$_offsetId.y'] ?? (pair[1] as num).toDouble(),
    );
  }

  void _drag(String id, double? value) => setState(
    () => value == null ? _dragging.remove(id) : _dragging[id] = value,
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final rows = InputRows(context, _controller, _dragging, _drag);
      final colors = Theme.of(context).colorScheme;
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        conflictTitle: 'Window appearance differs from saved Settings',
        hero: InputHero(
          caption:
              'The front window is focused. Changes apply to open '
              'windows right away.',
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CustomPaint(
                key: const ValueKey('window-appearance-preview'),
                painter: WindowsPainter(
                  colors: colors,
                  rounding: _number('window-appearance.rounding', 0),
                  roundingPower: _number('window-appearance.rounding-power', 2),
                  border: _number('multitasking.border-size', 1),
                  activeBorder: _color('window-appearance.active-border'),
                  inactiveBorder: _color('window-appearance.inactive-border'),
                  activeOpacity: _number('window-appearance.active-opacity', 1),
                  inactiveOpacity: _number(
                    'window-appearance.inactive-opacity',
                    1,
                  ),
                  dim: _on('window-appearance.dim-inactive')
                      ? _number('window-appearance.dim-strength', 0)
                      : 0,
                  shadow: _on('window-appearance.shadow')
                      ? _color('window-appearance.shadow-color')
                      : null,
                  shadowRange: _number('window-appearance.shadow-range', 0),
                  shadowScale: _number('window-appearance.shadow-scale', 1),
                  shadowOffset: _offset,
                  glow: _on('window-appearance.glow')
                      ? _color('window-appearance.glow-color')
                      : null,
                  glowRange: _number('window-appearance.glow-range', 0),
                ),
              ),
            ),
          ),
        ),
        isVisible: (setting) => switch (setting.id) {
          'window-appearance.dim-strength' => _on(
            'window-appearance.dim-inactive',
          ),
          _ when setting.id.startsWith('window-appearance.shadow-') => _on(
            'window-appearance.shadow',
          ),
          _ when setting.id.startsWith('window-appearance.glow-') => _on(
            'window-appearance.glow',
          ),
          _ => true,
        },
        controlBuilder: (setting) => switch (setting.id) {
          _offsetId => _OffsetRow(
            setting: setting,
            offset: _offset,
            enabled: _controller.canChange,
            onDrag: _drag,
            onDone: (x, y) => _controller.set(_offsetId, [x, y]),
          ),
          'window-appearance.rounding-power' => rows.build(
            setting,
            subtitle: switch (_number(setting.id, 2)) {
              < 1.5 => 'Bevelled corners',
              < 2.5 => 'Circular corners',
              _ => 'Smooth squircle corners',
            },
          ),
          'window-appearance.inactive-border' => rows.build(
            setting,
            subtitle: 'Border width is set in Multitasking',
          ),
          'window-appearance.fullscreen-opacity' => rows.build(
            setting,
            subtitle: 'Video and games usually look best fully opaque',
          ),
          'window-appearance.dim-special' => rows.build(
            setting,
            subtitle: 'While the scratchpad workspace is shown',
          ),
          'window-appearance.shadow-render-power' ||
          'window-appearance.glow-render-power' => rows.build(
            setting,
            subtitle: 'Higher values fade out faster near the window',
          ),
          'window-appearance.border-part-of-window' => rows.build(
            setting,
            subtitle:
                'Borders take space from the window instead of being drawn '
                'outside it',
          ),
          _ => rows.build(setting),
        },
      );
    },
  );
}

/// Horizontal and vertical shadow offset; only the release writes.
class _OffsetRow extends StatelessWidget {
  const _OffsetRow({
    required this.setting,
    required this.offset,
    required this.enabled,
    required this.onDrag,
    required this.onDone,
  });
  final SettingSpec setting;
  final (double, double) offset;
  final bool enabled;
  final void Function(String id, double? value) onDrag;
  final void Function(int x, int y) onDone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (x, y) = offset;
    Widget axis(String label, String key, double value) => Row(
      children: [
        SizedBox(width: 88, child: Text(label, style: text.bodySmall)),
        Expanded(
          child: Slider(
            key: ValueKey('$_offsetId-$key'),
            value: value.clamp(-20, 20).toDouble(),
            min: -20,
            max: 20,
            divisions: 40,
            label: '${value.round()} px',
            onChanged: enabled ? (v) => onDrag('$_offsetId.$key', v) : null,
            onChangeEnd: enabled
                ? (v) {
                    onDrag('$_offsetId.$key', null);
                    onDone(
                      key == 'x' ? v.round() : x.round(),
                      key == 'y' ? v.round() : y.round(),
                    );
                  }
                : null,
          ),
        ),
      ],
    );
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(setting.title, style: text.bodyLarge),
          Text(
            'Right ${x.round()} px, down ${y.round()} px',
            style: text.bodySmall,
          ),
        ],
      ),
      control: SizedBox(
        width: 260,
        child: Column(
          children: [axis('Horizontal', 'x', x), axis('Vertical', 'y', y)],
        ),
      ),
    );
  }
}

/// A desktop with an inactive window behind the focused one.
///
/// Pixel sizes are drawn at half scale, so corners and borders stay visible in
/// a small preview.
class WindowsPainter extends CustomPainter {
  WindowsPainter({
    required this.colors,
    required this.rounding,
    required this.roundingPower,
    required this.border,
    required this.activeBorder,
    required this.inactiveBorder,
    required this.activeOpacity,
    required this.inactiveOpacity,
    required this.dim,
    required this.shadow,
    required this.shadowRange,
    required this.shadowScale,
    required this.shadowOffset,
    required this.glow,
    required this.glowRange,
  });
  final ColorScheme colors;
  final double rounding;
  final double roundingPower;
  final double border;
  final Color? activeBorder;
  final Color? inactiveBorder;
  final double activeOpacity;
  final double inactiveOpacity;
  final double dim;
  final Color? shadow;
  final double shadowRange;
  final double shadowScale;
  final (double, double) shadowOffset;
  final Color? glow;
  final double glowRange;

  /// A rectangle whose corners follow `|x|^p + |y|^p = r^p`, as Hyprland draws them.
  static Path shape(Rect rect, double radius, double power) {
    final r = radius.clamp(0, rect.shortestSide / 2).toDouble();
    if (r == 0) return Path()..addRect(rect);
    final path = Path();
    final corners = [
      (Offset(rect.right - r, rect.top + r), -math.pi / 2),
      (Offset(rect.right - r, rect.bottom - r), 0.0),
      (Offset(rect.left + r, rect.bottom - r), math.pi / 2),
      (Offset(rect.left + r, rect.top + r), math.pi),
    ];
    var first = true;
    for (final (center, start) in corners) {
      for (var i = 0; i <= 12; i++) {
        final t = start + i / 12 * math.pi / 2;
        final c = math.cos(t), s = math.sin(t);
        final point =
            center +
            Offset(
              c.sign * r * math.pow(c.abs(), 2 / power),
              s.sign * r * math.pow(s.abs(), 2 / power),
            );
        if (first) {
          path.moveTo(point.dx, point.dy);
          first = false;
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final factor = size.width / 640;
    final screen = RRect.fromRectAndRadius(
      Offset.zero & size,
      const .circular(16),
    );
    canvas.save();
    canvas.clipRRect(screen);
    canvas.drawRRect(screen, Paint()..color = colors.tertiaryContainer);
    // Shapes behind the windows make transparency visible.
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.2),
      size.height * 0.28,
      Paint()..color = colors.tertiary,
    );
    canvas.drawCircle(
      Offset(size.width * 0.2, size.height * 0.92),
      size.height * 0.3,
      Paint()..color = colors.primary,
    );
    final back = Rect.fromLTWH(
      size.width * 0.08,
      size.height * 0.1,
      size.width * 0.5,
      size.height * 0.6,
    );
    final front = Rect.fromLTWH(
      size.width * 0.4,
      size.height * 0.3,
      size.width * 0.52,
      size.height * 0.58,
    );
    _window(canvas, back, factor, active: false);
    _window(canvas, front, factor, active: true);
    canvas.restore();
  }

  void _window(
    Canvas canvas,
    Rect rect,
    double factor, {
    required bool active,
  }) {
    final path = shape(rect, rounding * factor, roundingPower);
    if (shadow case final color?) {
      final grown = Rect.fromCenter(
        center: rect.center,
        width: rect.width * shadowScale,
        height: rect.height * shadowScale,
      ).shift(Offset(shadowOffset.$1, shadowOffset.$2) * factor);
      canvas.drawPath(
        shape(grown, rounding * factor, roundingPower),
        Paint()
          ..color = color
          ..maskFilter = MaskFilter.blur(
            .normal,
            math.max(shadowRange * factor / 2, 0.1),
          ),
      );
    }
    final opacity = (active ? activeOpacity : inactiveOpacity).clamp(0.0, 1.0);
    canvas.drawPath(
      path,
      Paint()
        ..color = (active ? colors.surface : colors.surfaceContainerLow)
            .withValues(alpha: opacity),
    );
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left + 10, rect.top + 10, rect.width * 0.4, 5),
        const .circular(2.5),
      ),
      Paint()..color = colors.outlineVariant,
    );
    if (glow case final color?) {
      canvas.drawPath(
        path,
        Paint()
          ..style = .stroke
          ..strokeWidth = math.max(glowRange * factor, 1)
          ..color = color
          ..maskFilter = MaskFilter.blur(
            .normal,
            math.max(glowRange * factor / 2, 0.1),
          ),
      );
    }
    if (!active && dim > 0) {
      canvas.drawPath(
        path,
        Paint()..color = Colors.black.withValues(alpha: dim),
      );
    }
    canvas.restore();
    final stroke = border <= 0 ? 0.0 : math.max(border * factor, 1.0);
    final color = active ? activeBorder : inactiveBorder;
    if (stroke > 0 && color != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = .stroke
          ..strokeWidth = stroke
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(WindowsPainter old) =>
      old.colors != colors ||
      old.rounding != rounding ||
      old.roundingPower != roundingPower ||
      old.border != border ||
      old.activeBorder != activeBorder ||
      old.inactiveBorder != inactiveBorder ||
      old.activeOpacity != activeOpacity ||
      old.inactiveOpacity != inactiveOpacity ||
      old.dim != dim ||
      old.shadow != shadow ||
      old.shadowRange != shadowRange ||
      old.shadowScale != shadowScale ||
      old.shadowOffset != shadowOffset ||
      old.glow != glow ||
      old.glowRange != glowRange;
}
