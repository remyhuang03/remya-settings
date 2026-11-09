import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/application/feature_options_controller.dart';
import 'input_widgets.dart';

/// Taps, clicks, scrolling and workspace swipes for every connected touchpad.
class TouchpadPage extends StatefulWidget {
  const TouchpadPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<TouchpadPage> createState() => _TouchpadPageState();
}

class _TouchpadPageState extends State<TouchpadPage> {
  late final _controller = FeatureOptionsController(widget.client)..reload();
  final _dragging = <String, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _tapCaption() {
    if (_controller.option('touchpad.tap-to-click') != true) {
      return 'Tapping does nothing; press the touchpad to click.';
    }
    final middle = _controller.option('touchpad.tap-buttons') == 'lmr';
    return 'Tap with one finger to click, two fingers to ${middle ? 'middle' : 'right'} click '
        'and three fingers to ${middle ? 'right' : 'middle'} click.';
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
      final fingers = _controller.option('touchpad.click-method') == true;
      final tap = _controller.option('touchpad.tap-to-click') == true;
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        hero: InputHero(
          caption:
              '${fingers ? 'Press with two fingers to right click.' : 'Press the lower right corner to right click.'} '
              '${_tapCaption()}',
          child: SizedBox(
            height: 170,
            child: CustomPaint(
              key: const ValueKey('touchpad-diagram'),
              size: const Size(280, 170),
              painter: _TouchpadPainter(
                colors: Theme.of(context).colorScheme,
                text: Theme.of(context).textTheme,
                fingers: fingers,
              ),
            ),
          ),
        ),
        // Tap options only exist while tapping clicks, and drag lock only while tap-dragging.
        isVisible: (setting) => switch (setting.id) {
          'touchpad.tap-buttons' || 'touchpad.tap-and-drag' => tap,
          'touchpad.drag-lock' =>
            tap && _controller.option('touchpad.tap-and-drag') == true,
          _ => true,
        },
        controlBuilder: (setting) => switch (setting.id) {
          'touchpad.devices' => rows.devices(
            setting,
            _controller.names('touchpads'),
            'No touchpad is connected. These settings apply when one is.',
          ),
          'touchpad.tap-buttons' when _controller.option(setting.id) == '' =>
            rows.build(setting, subtitle: 'Device default: right click'),
          'touchpad.swipe-invert' => rows.build(
            setting,
            subtitle: _controller.option(setting.id) == true
                ? 'Swipe left to go to the next workspace.'
                : 'Swipe right to go to the next workspace.',
          ),
          _ => rows.build(setting),
        },
      );
    },
  );
}

class _TouchpadPainter extends CustomPainter {
  _TouchpadPainter({
    required this.colors,
    required this.text,
    required this.fingers,
  });
  final ColorScheme colors;
  final TextTheme text;
  final bool fingers;

  void _label(Canvas canvas, String value, Offset center, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: text.labelMedium?.copyWith(color: color),
      ),
      textDirection: .ltr,
      textAlign: .center,
    )..layout(maxWidth: 110);
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pad = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: 260,
      height: 160,
    );
    final shape = RRect.fromRectAndRadius(pad, const .circular(20));
    canvas.drawRRect(shape, Paint()..color = colors.surfaceContainerHighest);
    if (fingers) {
      // One, two and three fingers pressed together.
      final groups = [
        (1, 'Click', colors.primary),
        (2, 'Right click', colors.tertiary),
        (3, 'Middle click', colors.secondary),
      ];
      for (var g = 0; g < groups.length; g++) {
        final (count, name, color) = groups[g];
        final center = Offset(
          pad.left + pad.width * (g + 0.5) / 3,
          pad.center.dy - 12,
        );
        for (var i = 0; i < count; i++) {
          canvas.drawCircle(
            center + Offset((i - (count - 1) / 2) * 18, 0),
            7,
            Paint()..color = color,
          );
        }
        _label(
          canvas,
          name,
          center + const Offset(0, 30),
          colors.onSurfaceVariant,
        );
      }
    } else {
      final split = pad.bottom - 46;
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(
        Rect.fromLTRB(pad.left, split, pad.center.dx, pad.bottom),
        Paint()..color = colors.primaryContainer,
      );
      canvas.drawRect(
        Rect.fromLTRB(pad.center.dx, split, pad.right, pad.bottom),
        Paint()..color = colors.tertiaryContainer,
      );
      canvas.restore();
      final line = Paint()
        ..color = colors.outline
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(pad.left, split), Offset(pad.right, split), line);
      canvas.drawLine(
        Offset(pad.center.dx, split),
        Offset(pad.center.dx, pad.bottom),
        line,
      );
      _label(
        canvas,
        'Click',
        Offset(pad.left + pad.width / 4, split + 23),
        colors.onPrimaryContainer,
      );
      _label(
        canvas,
        'Right click',
        Offset(pad.right - pad.width / 4, split + 23),
        colors.onTertiaryContainer,
      );
      _label(
        canvas,
        'Press anywhere else to click',
        Offset(pad.center.dx, pad.top + 50),
        colors.onSurfaceVariant,
      );
    }
    canvas.drawRRect(
      shape,
      Paint()
        ..color = colors.outline
        ..style = .stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TouchpadPainter old) =>
      old.fingers != fingers || old.colors != colors;
}
