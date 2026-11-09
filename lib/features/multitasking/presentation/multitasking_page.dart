import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';

const _layoutId = 'multitasking.layout';

/// Window layout, spacing, borders, snapping and resizing for every workspace.
class MultitaskingPage extends StatefulWidget {
  const MultitaskingPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<MultitaskingPage> createState() => _MultitaskingPageState();
}

class _MultitaskingPageState extends State<MultitaskingPage> {
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
  double _number(String id) {
    if (_dragging[id] case final held?) return held;
    return switch (_controller.option(id)) {
      final num v => v.toDouble(),
      final List<Object?> sides => (sides.first as num? ?? 0).toDouble(),
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final rows = InputRows(
        context,
        _controller,
        _dragging,
        (id, value) => setState(
          () => value == null ? _dragging.remove(id) : _dragging[id] = value,
        ),
      );
      final layout = _controller.option(_layoutId);
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        conflictTitle: 'Desktop settings differ from saved Settings',
        hero: InputHero(
          caption: _caption(layout),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: CustomPaint(
                key: const ValueKey('multitasking-preview'),
                painter: LayoutPainter(
                  layout: '$layout',
                  gapsIn: _number('multitasking.gaps-in'),
                  gapsOut: _number('multitasking.gaps-out'),
                  border: _number('multitasking.border-size'),
                  colors: Theme.of(context).colorScheme,
                ),
              ),
            ),
          ),
        ),
        isVisible: (setting) => switch (setting.id) {
          'multitasking.snap-window-gap' ||
          'multitasking.snap-monitor-gap' ||
          'multitasking.snap-respect-gaps' ||
          'multitasking.snap-border-overlap' =>
            _controller.option('multitasking.snap') == true,
          'multitasking.border-grab-area' || 'multitasking.border-hover-icon' =>
            _controller.option('multitasking.resize-on-border') == true,
          _ => true,
        },
        controlBuilder: (setting) => switch (setting.id) {
          _layoutId => _LayoutChooser(
            setting: setting,
            value: layout,
            enabled: _controller.canChange,
            onSelected: (value) => _controller.set(_layoutId, value),
          ),
          'multitasking.gaps-workspaces' => rows.build(
            setting,
            subtitle: 'Shown while a workspace slides in',
          ),
          'multitasking.no-focus-fallback' => rows.build(
            setting,
            subtitle:
                'Moving focus toward an empty side does nothing instead of '
                'choosing the nearest window',
          ),
          'multitasking.allow-tearing' => rows.build(
            setting,
            subtitle:
                'Lets games that ask for it skip vertical sync for lower '
                'latency',
          ),
          'multitasking.modal-parent-blocking' => rows.build(
            setting,
            subtitle: 'The window that opened a dialog waits until it closes',
          ),
          _ => rows.build(setting),
        },
      );
    },
  );

  String _caption(Object? layout) => switch (layout) {
    'dwindle' =>
      'Dwindle splits the focused window in two for each new window.',
    'master' =>
      'Master keeps one large window and stacks the others beside it.',
    'scrolling' =>
      'Scrolling places windows in columns on a strip wider than the screen.',
    'monocle' =>
      'Monocle shows one window at a time; switch between them to see others.',
    null => '',
    _ => 'A custom layout from your configuration is in use.',
  };
}

const _layouts = [
  ('dwindle', 'Dwindle'),
  ('master', 'Master'),
  ('scrolling', 'Scrolling'),
  ('monocle', 'Monocle'),
];

/// The four built-in layouts as selectable thumbnails.
class _LayoutChooser extends StatelessWidget {
  const _LayoutChooser({
    required this.setting,
    required this.value,
    required this.enabled,
    required this.onSelected,
  });
  final SettingSpec setting;
  final Object? value;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      key: ValueKey(setting.id),
      padding: const .symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(setting.title, style: text.bodyLarge),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final (id, label) in _layouts)
                Semantics(
                  selected: value == id,
                  button: true,
                  child: Material(
                    color: value == id
                        ? colors.secondaryContainer
                        : colors.surfaceContainerHigh,
                    shape: RoundedRectangleBorder(
                      borderRadius: .circular(16),
                      side: BorderSide(
                        color: value == id
                            ? colors.primary
                            : colors.outlineVariant,
                        width: value == id ? 2 : 1,
                      ),
                    ),
                    clipBehavior: .antiAlias,
                    child: InkWell(
                      key: ValueKey('layout-$id'),
                      onTap: enabled && value != id
                          ? () => onSelected(id)
                          : null,
                      child: Padding(
                        padding: const .all(12),
                        child: Column(
                          spacing: 8,
                          children: [
                            SizedBox(
                              width: 112,
                              height: 63,
                              child: CustomPaint(
                                painter: LayoutPainter(
                                  layout: id,
                                  gapsIn: 6,
                                  gapsOut: 6,
                                  border: 2,
                                  colors: colors,
                                  scale: 1,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisSize: .min,
                              spacing: 4,
                              children: [
                                if (value == id)
                                  Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: colors.onSecondaryContainer,
                                  ),
                                Text(label, style: text.labelLarge),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A screen with windows arranged by [layout]; the first one is focused.
///
/// Gaps and borders are drawn at [scale] of their pixel size, so the preview
/// stays proportional to a 1280 pixel wide screen at its default size.
class LayoutPainter extends CustomPainter {
  LayoutPainter({
    required this.layout,
    required this.gapsIn,
    required this.gapsOut,
    required this.border,
    required this.colors,
    this.scale,
  });
  final String layout;
  final double gapsIn;
  final double gapsOut;
  final double border;
  final ColorScheme colors;
  final double? scale;

  List<Rect> _windows(Rect area, double gap) {
    final half = gap / 2;
    switch (layout) {
      case 'master':
        // One large window beside a stack of the others.
        final split = area.left + area.width * 0.58;
        final third = (area.height - 2 * gap) / 3;
        return [
          Rect.fromLTRB(area.left, area.top, split - half, area.bottom),
          for (var i = 0; i < 3; i++)
            Rect.fromLTWH(
              split + half,
              area.top + i * (third + gap),
              area.right - split - half,
              third,
            ),
        ];
      case 'scrolling':
        final width = area.width * 0.62;
        return [
          Rect.fromLTWH(area.left, area.top, width, area.height),
          Rect.fromLTWH(area.left + width + gap, area.top, width, area.height),
        ];
      case 'monocle':
        return [area];
      default:
        // Each new window halves the previous one, turning like a spiral.
        final split = area.center.dx;
        final middle = area.center.dy;
        final quarter = split + half + (area.right - split - half) / 2;
        return [
          Rect.fromLTRB(area.left, area.top, split - half, area.bottom),
          Rect.fromLTRB(split + half, area.top, area.right, middle - half),
          Rect.fromLTRB(
            split + half,
            middle + half,
            quarter - half,
            area.bottom,
          ),
          Rect.fromLTRB(quarter + half, middle + half, area.right, area.bottom),
        ];
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final factor = scale ?? size.width / 1280;
    final screen = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(scale == null ? 16 : 8),
    );
    canvas.drawRRect(screen, Paint()..color = colors.tertiaryContainer);
    canvas.save();
    canvas.clipRRect(screen);
    final outer = (gapsOut * factor).clamp(0, size.shortestSide / 4).toDouble();
    final area = (Offset.zero & size).deflate(outer);
    final windows = _windows(area, (gapsIn * 2 * factor).toDouble());
    final stroke = border <= 0 ? 0.0 : (border * factor).clamp(1, 8).toDouble();
    for (var i = 0; i < windows.length; i++) {
      final rect = windows[i];
      final shape = RRect.fromRectAndRadius(rect, const .circular(6));
      canvas.drawRRect(
        shape,
        Paint()..color = i == 0 ? colors.surface : colors.surfaceContainerLow,
      );
      // A title bar suggests a window, so its size reads at a glance.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + 6,
            rect.top + 6,
            (rect.width - 12).clamp(0, 60).toDouble(),
            4,
          ),
          const .circular(2),
        ),
        Paint()..color = colors.outlineVariant,
      );
      if (stroke > 0) {
        canvas.drawRRect(
          shape.deflate(stroke / 2),
          Paint()
            ..style = .stroke
            ..strokeWidth = stroke
            ..color = i == 0 ? colors.primary : colors.outlineVariant,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LayoutPainter old) =>
      old.layout != layout ||
      old.gapsIn != gapsIn ||
      old.gapsOut != gapsOut ||
      old.border != border ||
      old.colors != colors;
}
