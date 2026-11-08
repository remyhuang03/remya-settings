import 'package:material_ui/material_ui.dart';

import 'shortcut_model.dart';

/// XKB keycodes and widths of a 15-unit-wide keyboard; code 0 is a gap.
const _rows = <List<(int, double)>>[
  [
    (9, 1),
    (0, 1),
    (67, 1),
    (68, 1),
    (69, 1),
    (70, 1),
    (0, .5),
    (71, 1),
    (72, 1),
    (73, 1),
    (74, 1),
    (0, .5),
    (75, 1),
    (76, 1),
    (95, 1),
    (96, 1),
  ],
  [
    (49, 1),
    (10, 1),
    (11, 1),
    (12, 1),
    (13, 1),
    (14, 1),
    (15, 1),
    (16, 1),
    (17, 1),
    (18, 1),
    (19, 1),
    (20, 1),
    (21, 1),
    (22, 2),
  ],
  [
    (23, 1.5),
    (24, 1),
    (25, 1),
    (26, 1),
    (27, 1),
    (28, 1),
    (29, 1),
    (30, 1),
    (31, 1),
    (32, 1),
    (33, 1),
    (34, 1),
    (35, 1),
    (51, 1.5),
  ],
  [
    (66, 1.75),
    (38, 1),
    (39, 1),
    (40, 1),
    (41, 1),
    (42, 1),
    (43, 1),
    (44, 1),
    (45, 1),
    (46, 1),
    (47, 1),
    (48, 1),
    (36, 2.25),
  ],
  [
    (50, 2.25),
    (52, 1),
    (53, 1),
    (54, 1),
    (55, 1),
    (56, 1),
    (57, 1),
    (58, 1),
    (59, 1),
    (60, 1),
    (61, 1),
    (62, 2.75),
  ],
  [
    (37, 1.5),
    (133, 1.5),
    (64, 1.5),
    (65, 6),
    (108, 1.5),
    (134, 1.5),
    (105, 1.5),
  ],
];

const _modifierCodes = {
  50: 'SHIFT',
  62: 'SHIFT',
  37: 'CTRL',
  105: 'CTRL',
  64: 'ALT',
  108: 'ALT',
  133: 'SUPER',
  134: 'SUPER',
};

/// A keyboard showing which keys have a shortcut with the chosen modifiers.
/// Modifier keys toggle the filter; other keys select a key to inspect.
class KeyboardMap extends StatelessWidget {
  const KeyboardMap({
    super.key,
    required this.shortcuts,
    required this.labels,
    required this.modifiers,
    required this.selected,
    required this.onModifier,
    required this.onKey,
  });
  final List<LiveShortcut> shortcuts;
  final Map<String, dynamic> labels;
  final Set<String> modifiers;
  final int? selected;
  final ValueChanged<String> onModifier;
  final ValueChanged<int> onKey;

  /// Shortcuts on [code] with exactly the chosen modifiers, in the default mode.
  static List<LiveShortcut> on(
    List<LiveShortcut> shortcuts,
    int code,
    Set<String> modifiers,
  ) => [
    for (final s in shortcuts)
      if (s.code == code &&
          s.submap.isEmpty &&
          s.modifiers.toSet().containsAll(modifiers) &&
          modifiers.containsAll(s.modifiers))
        s,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final unit = (constraints.maxWidth / 15).clamp(18.0, 52.0);
        Widget key(int code, double width) {
          final size = Size(unit * width - 4, unit * .82);
          if (code == 0) {
            return SizedBox(width: unit * width, height: size.height);
          }
          final modifier = _modifierCodes[code];
          final bound = modifier == null
              ? on(shortcuts, code, modifiers)
              : const <LiveShortcut>[];
          final active = modifier != null && modifiers.contains(modifier);
          final custom = bound.any((s) => s.custom);
          final (background, foreground) = switch (()) {
            _ when active => (colors.primary, colors.onPrimary),
            _ when custom => (
              colors.tertiaryContainer,
              colors.onTertiaryContainer,
            ),
            _ when bound.isNotEmpty => (
              colors.primaryContainer,
              colors.onPrimaryContainer,
            ),
            _ => (colors.surfaceContainerHigh, colors.onSurfaceVariant),
          };
          final label = switch (code) {
            65 => 'Space',
            _ when modifier != null => modifierLabels[modifier]!,
            _ => labels['$code'] as String? ?? '',
          };
          final hint = modifier != null
              ? '$label: ${active ? 'shown' : 'not shown'} in the map'
              : bound.isEmpty
              ? '$label: free'
              : '$label: ${bound.map((s) => s.title).join(', ')}';
          return Padding(
            padding: const .all(2),
            child: Tooltip(
              message: hint,
              child: Semantics(
                selected: active || selected == code,
                label: hint,
                button: true,
                excludeSemantics: true,
                child: Material(
                  color: background,
                  shape: RoundedRectangleBorder(
                    borderRadius: .circular(unit * .2),
                    side: selected == code
                        ? BorderSide(color: colors.primary, width: 2.5)
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    key: ValueKey('keyboard-key-$code'),
                    borderRadius: .circular(unit * .2),
                    onTap: () =>
                        modifier != null ? onModifier(modifier) : onKey(code),
                    child: SizedBox.fromSize(
                      size: size,
                      child: Center(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: .clip,
                          style: text.labelSmall?.copyWith(
                            color: foreground,
                            fontSize: (unit * .3).clamp(8, 13),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Column(
          children: [
            for (final row in _rows)
              Row(
                mainAxisAlignment: .center,
                children: [for (final (code, width) in row) key(code, width)],
              ),
          ],
        );
      },
    );
  }
}
