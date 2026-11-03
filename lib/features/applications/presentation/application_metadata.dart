import 'package:material_ui/material_ui.dart';

String formatBytes(num bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB', 'EiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${unit == 0 ? value.round() : value.toStringAsFixed(1)} ${units[unit]}';
}

String applicationSourceLabel(String source) => switch (source) {
  'pacman' => 'System package',
  'manual' => 'Manual installation',
  'appimage' => 'AppImage',
  _ => source,
};

class ApplicationMetadata extends StatelessWidget {
  const ApplicationMetadata({
    super.key,
    this.source,
    this.version,
    this.size,
    this.notice,
  });
  final String? source;
  final String? version;
  final int? size;
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, background, foreground) in [
          if (source case final source?)
            (source, colors.secondaryContainer, colors.onSecondaryContainer),
          if (version case final version?)
            (version, colors.tertiaryContainer, colors.onTertiaryContainer),
          if (size case final size?)
            (
              formatBytes(size),
              colors.primaryContainer,
              colors.onPrimaryContainer,
            ),
          if (notice case final notice?)
            (notice, colors.surfaceContainerHighest, colors.onSurface),
        ])
          Chip(
            label: Text(label),
            labelStyle: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: foreground),
            backgroundColor: background,
            side: BorderSide.none,
            shape: const RoundedRectangleBorder(
              borderRadius: .all(.circular(8)),
            ),
            visualDensity: .compact,
            materialTapTargetSize: .shrinkWrap,
          ),
      ],
    );
  }
}
