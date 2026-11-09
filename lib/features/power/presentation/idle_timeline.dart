import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';

/// Short duration text such as `10 min` or `1 h 30 min`.
String idleDuration(int seconds) {
  if (seconds < 60) return '$seconds s';
  final hours = seconds ~/ 3600;
  final minutes = seconds % 3600 ~/ 60;
  return [if (hours > 0) '$hours h', if (minutes > 0) '$minutes min'].join(' ');
}

/// What happens after how long without input, on one shared time axis.
class IdleTimeline extends StatelessWidget {
  const IdleTimeline({
    super.key,
    required this.screen,
    required this.lock,
    required this.sleep,
    required this.lockBeforeSleep,
  });

  /// Seconds; 0 means the step never happens.
  final int screen;
  final int lock;
  final int sleep;
  final bool lockBeforeSleep;

  List<_Step> get _steps => [
    if (screen > 0)
      (
        seconds: screen,
        label: 'Screen off',
        sentence: 'the screen turns off',
        icon: Icons.monitor_outlined,
      ),
    if (lock > 0)
      (
        seconds: lock,
        label: 'Lock',
        sentence: 'the session locks',
        icon: Icons.lock_outline_rounded,
      ),
    if (sleep > 0)
      (
        seconds: sleep,
        label: 'Sleep',
        sentence: lockBeforeSleep
            ? 'the computer locks and sleeps'
            : 'the computer sleeps',
        icon: Icons.bedtime_outlined,
      ),
  ]..sort((a, b) => a.seconds.compareTo(b.seconds));

  /// The whole timeline as sentences, for the caption and screen readers.
  String get caption {
    final steps = _steps;
    if (steps.isEmpty) {
      return 'The screen stays on and the computer never sleeps on its own.';
    }
    return [
      for (final step in steps)
        'After ${idleDuration(step.seconds)}, ${step.sentence}.',
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final steps = _steps;
    return Semantics(
      label: caption,
      child: ExcludeSemantics(
        child: SizedBox(
          height: 96,
          child: CustomPaint(
            key: const ValueKey('idle-timeline'),
            painter: _TimelinePainter(steps: steps, colors: colors, text: text),
            size: const Size(double.infinity, 96),
          ),
        ),
      ),
    );
  }
}

typedef _Step = ({int seconds, String label, String sentence, IconData icon});

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({
    required this.steps,
    required this.colors,
    required this.text,
  });
  final List<_Step> steps;
  final ColorScheme colors;
  final TextTheme text;

  void _text(Canvas canvas, String value, Offset center, TextStyle? style) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textAlign: .center,
      textDirection: .ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  void _icon(Canvas canvas, IconData icon, Offset center, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          fontSize: 18,
          color: color,
        ),
      ),
      textDirection: .ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 48.0;
    const y = 40.0;
    final width = size.width - inset * 2;
    final track = Paint()
      ..color = colors.surfaceContainerHighest
      ..strokeWidth = 8
      ..strokeCap = .round;
    canvas.drawLine(const Offset(inset, y), Offset(inset + width, y), track);
    _text(canvas, 'Last input', Offset(inset, y + 30), text.labelSmall);
    _icon(
      canvas,
      Icons.touch_app_outlined,
      const Offset(inset, y - 26),
      colors.onSurfaceVariant,
    );
    if (steps.isEmpty) return;
    // A little room past the last step keeps its label inside the track.
    final end = steps.last.seconds * 1.08;
    final active = Paint()
      ..color = colors.primary
      ..strokeWidth = 8
      ..strokeCap = .round;
    canvas.drawLine(
      const Offset(inset, y),
      Offset(inset + width * steps.last.seconds / end, y),
      active,
    );
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      final x = inset + width * step.seconds / end;
      canvas.drawCircle(Offset(x, y), 9, Paint()..color = colors.primary);
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = colors.onPrimary);
      // Steps at the same moment share one marker; their labels stack.
      final shared = steps.where((s) => s.seconds == step.seconds).toList();
      final index = shared.indexOf(step);
      _icon(
        canvas,
        step.icon,
        Offset(x + (index - (shared.length - 1) / 2) * 22, y - 26),
        colors.primary,
      );
      if (index == 0) {
        _text(
          canvas,
          '${shared.map((s) => s.label).join(', ')}\n${idleDuration(step.seconds)}',
          Offset(x, y + 34),
          text.labelSmall?.copyWith(color: colors.onSurface),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TimelinePainter old) =>
      old.colors != colors || !listEquals(old.steps, steps);
}
