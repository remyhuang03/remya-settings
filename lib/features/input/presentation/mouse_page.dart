import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/application/feature_options_controller.dart';
import 'input_widgets.dart';

/// Mouse buttons, pointer, scrolling and focus, applied to every connected mouse.
class MousePage extends StatefulWidget {
  const MousePage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<MousePage> createState() => _MousePageState();
}

class _MousePageState extends State<MousePage> {
  late final _controller = FeatureOptionsController(widget.client)..reload();
  final _dragging = <String, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      final leftHanded = _controller.option('mouse.primary-button') == true;
      final natural = _controller.option('mouse.natural-scroll') == true;
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        hero: InputHero(
          caption:
              '${leftHanded ? 'Right' : 'Left'} button selects and drags. '
              'Rolling the wheel toward you moves content ${natural ? 'down, like a touchscreen' : 'up'}.',
          child: SizedBox(
            height: 180,
            child: CustomPaint(
              key: const ValueKey('mouse-diagram'),
              size: const Size(280, 180),
              painter: _MousePainter(
                colors: Theme.of(context).colorScheme,
                text: Theme.of(context).textTheme,
                leftHanded: leftHanded,
                natural: natural,
              ),
            ),
          ),
        ),
        isVisible: (setting) => switch (setting.id) {
          // Refocusing on hover only exists while focus follows the pointer.
          'mouse.refocus' => _controller.option('mouse.focus-follows') == 1,
          _ => true,
        },
        controlBuilder: (setting) => switch (setting.id) {
          'mouse.devices' => rows.devices(
            setting,
            _controller.names('mice'),
            'No mouse is connected.',
          ),
          'mouse.acceleration' when _controller.option(setting.id) == '' =>
            rows.build(setting, subtitle: 'Device default until you choose'),
          'mouse.focus-follows' => rows.build(
            setting,
            subtitle: switch (_controller.option(setting.id)) {
              1 => 'The window under the pointer receives the keyboard.',
              2 => 'Hovered windows scroll; clicking moves the keyboard focus.',
              0 => 'Moving the pointer never changes focus.',
              3 => 'Clicking does not move the keyboard focus either.',
              _ => null,
            },
          ),
          _ => rows.build(setting),
        },
      );
    },
  );
}

class _MousePainter extends CustomPainter {
  _MousePainter({
    required this.colors,
    required this.text,
    required this.leftHanded,
    required this.natural,
  });
  final ColorScheme colors;
  final TextTheme text;
  final bool leftHanded;
  final bool natural;

  void _label(
    Canvas canvas,
    String value,
    Offset at,
    Color color, {
    bool center = true,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: text.labelMedium?.copyWith(color: color),
      ),
      textDirection: .ltr,
    )..layout();
    painter.paint(
      canvas,
      at - Offset(center ? painter.width / 2 : 0, painter.height / 2),
    );
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Paint paint) {
    canvas.drawLine(from, to, paint);
    final direction = (to - from) / (to - from).distance;
    final side = Offset(-direction.dy, direction.dx) * 6;
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo((to - direction * 9 + side).dx, (to - direction * 9 + side).dy)
        ..lineTo((to - direction * 9 - side).dx, (to - direction * 9 - side).dy)
        ..close(),
      Paint()..color = paint.color,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final mouse = Rect.fromLTWH(size.width / 2 - 110, 10, 100, 160);
    final body = RRect.fromRectAndRadius(mouse, const .circular(50));
    final outline = Paint()
      ..color = colors.outline
      ..style = .stroke
      ..strokeWidth = 2;
    canvas.drawRRect(body, Paint()..color = colors.surfaceContainerHighest);
    final split = mouse.top + 66;
    for (final left in [true, false]) {
      final primary = left != leftHanded;
      final half = Rect.fromLTRB(
        left ? mouse.left : mouse.center.dx,
        mouse.top,
        left ? mouse.center.dx : mouse.right,
        split,
      );
      canvas.save();
      canvas.clipRRect(body);
      canvas.drawRect(
        half,
        Paint()..color = primary ? colors.primary : colors.secondaryContainer,
      );
      canvas.restore();
      _label(
        canvas,
        primary ? 'Primary' : 'Menu',
        Offset(half.center.dx, split + 14),
        primary ? colors.primary : colors.onSurfaceVariant,
      );
    }
    canvas.drawLine(
      Offset(mouse.left, split),
      Offset(mouse.right, split),
      outline,
    );
    canvas.drawLine(
      Offset(mouse.center.dx, mouse.top),
      Offset(mouse.center.dx, split),
      outline,
    );
    final wheel = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(mouse.center.dx, mouse.top + 34),
        width: 14,
        height: 30,
      ),
      const .circular(7),
    );
    canvas.drawRRect(wheel, Paint()..color = colors.tertiary);
    canvas.drawRRect(body, outline);

    // The wheel rolled toward the user, and where the content goes.
    final accent = Paint()
      ..color = colors.tertiary
      ..strokeWidth = 2.5;
    final page = Rect.fromLTWH(size.width / 2 + 30, 30, 76, 110);
    canvas.drawRRect(
      RRect.fromRectAndRadius(page, const .circular(10)),
      Paint()..color = colors.surfaceContainerHigh,
    );
    for (var i = 0; i < 5; i++) {
      final y = page.top + 20 + i * 18;
      canvas.drawLine(
        Offset(page.left + 12, y),
        Offset(page.right - (i.isOdd ? 26 : 12), y),
        Paint()
          ..color = colors.outlineVariant
          ..strokeWidth = 4
          ..strokeCap = .round,
      );
    }
    _arrow(
      canvas,
      Offset(wheel.center.dx + 22, wheel.top),
      Offset(wheel.center.dx + 22, wheel.bottom + 10),
      accent,
    );
    final down = natural;
    _arrow(
      canvas,
      Offset(page.right + 16, down ? page.top + 30 : page.bottom - 30),
      Offset(page.right + 16, down ? page.bottom - 30 : page.top + 30),
      accent,
    );
    _label(
      canvas,
      'Content',
      Offset(page.center.dx, page.bottom + 14),
      colors.onSurfaceVariant,
    );
  }

  @override
  bool shouldRepaint(_MousePainter old) =>
      old.leftHanded != leftHanded ||
      old.natural != natural ||
      old.colors != colors;
}
