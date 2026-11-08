import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

import '../application/storage_controller.dart';
import '../../applications/presentation/application_metadata.dart';

/// Distinct chart hues harmonized toward the scheme's primary color.
List<Color> storageColors(ColorScheme colors) => [
  for (final hue in const [
    0xff1976d2, // Blue
    0xff388e3c, // Green
    0xfff57c00, // Orange
    0xffd81b60, // Pink
    0xff00897b, // Teal
    0xfffbc02d, // Yellow
    0xffd32f2f, // Red
    0xff7b1fa2, // Purple
    0xff00acc1, // Cyan
    0xff795548, // Brown
  ])
    Color(
      TonalPalette.fromHct(
        Hct.fromInt(Blend.harmonize(hue, colors.primary.toARGB32())),
      ).get(colors.brightness == Brightness.dark ? 75 : 40),
    ),
];

String percent(num part, num total) =>
    total > 0 ? '${(part * 100 / total).toStringAsFixed(1)}%' : '';

/// A rounded bar of proportional segments over a track that stands for free space.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.segments,
    required this.total,
    this.height = 16,
  });
  final List<(num, Color)> segments;
  final num total;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: .circular(height / 2),
      child: SizedBox(
        height: height,
        child: ColoredBox(
          color: colors.surfaceContainerHighest,
          child: LayoutBuilder(
            builder: (_, constraints) => Row(
              children: [
                for (final (bytes, color) in segments)
                  if (bytes > 0 && total > 0)
                    Container(
                      width: constraints.maxWidth * bytes / total,
                      // A hairline in the surface color separates neighbours.
                      decoration: BoxDecoration(
                        color: color,
                        border: Border(
                          right: BorderSide(
                            color: colors.surfaceContainerLowest,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One compact legend line: swatch, label and size; optionally opens something.
class StorageLegend extends StatelessWidget {
  const StorageLegend({
    super.key,
    required this.label,
    required this.bytes,
    required this.color,
    this.total,
    this.onTap,
    this.tooltip,
  });
  final String label;
  final num bytes;
  final num? total;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final row = InkWell(
      borderRadius: .circular(12),
      onTap: onTap,
      child: Padding(
        padding: const .symmetric(horizontal: 8, vertical: 10),
        child: Row(
          spacing: 12,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: .circle),
            ),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyLarge,
                overflow: .ellipsis,
              ),
            ),
            Text(formatBytes(bytes), style: theme.textTheme.bodyMedium),
            if (total != null)
              SizedBox(
                width: 52,
                child: Text(
                  percent(bytes, total!),
                  style: muted,
                  textAlign: .end,
                ),
              ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: onTap == null
                  ? Colors.transparent
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}

/// Lays children out in as many equal columns as fit [minWidth].
class LegendGrid extends StatelessWidget {
  const LegendGrid({super.key, required this.children, this.minWidth = 380});
  final List<Widget> children;
  final double minWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, constraints) {
      final columns = (constraints.maxWidth / minWidth).floor().clamp(1, 3);
      final width = constraints.maxWidth / columns;
      return Wrap(
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// The round tonal icon used to head storage cards.
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.size = 48});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        shape: .circle,
      ),
      child: Icon(icon, size: size / 2, color: colors.onSecondaryContainer),
    );
  }
}

/// A small labeled value, used for property grids.
class PropertyField extends StatelessWidget {
  const PropertyField({super.key, required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const .symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: .start,
        spacing: 2,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SelectableText(value, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

class StorageDate extends StatefulWidget {
  const StorageDate({
    super.key,
    required this.at,
    required this.controller,
    this.prefix = '',
    this.style,
  });
  final int at;
  final StorageController controller;
  final String prefix;
  final TextStyle? style;
  @override
  State<StorageDate> createState() => _StorageDateState();
}

class _StorageDateState extends State<StorageDate> {
  late Future<String> _date;
  late DateTime _time;
  void _load() {
    _time = DateTime.fromMillisecondsSinceEpoch(widget.at * 1000).toLocal();
    _date = widget.controller.formatDate(
      '${_time.year.toString().padLeft(4, '0')}-${_time.month.toString().padLeft(2, '0')}-${_time.day.toString().padLeft(2, '0')}',
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StorageDate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.at != widget.at) _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    future: _date,
    builder: (_, snapshot) => Text(
      snapshot.hasError
          ? 'Date unavailable: ${snapshot.error}'
          : '${widget.prefix}${snapshot.data ?? 'Formatting date…'} ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}',
      style: widget.style,
    ),
  );
}
