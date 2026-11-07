import 'package:material_ui/material_ui.dart';

import 'settings_widgets.dart';

class SettingsPreview extends StatelessWidget {
  const SettingsPreview(this.kind, {super.key});
  final String kind;

  @override
  Widget build(BuildContext context) {
    if (kind == 'none') return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    if (kind == 'display') return const _DisplayPreview();
    if (kind == 'personalization') return const _ThemePreview();
    final (icon, title, detail) = switch (kind) {
      'sound' => (
        Icons.graphic_eq_rounded,
        'Make room for every sound',
        'Output, input, and app volume.\nAudio devices have not been read.',
      ),
      'network' => (
        Icons.wifi_rounded,
        'Connect your world',
        'Connection preview.\nNetworks are not scanned or connected.',
      ),
      'devices' => (
        Icons.devices_other_rounded,
        'Your devices, organized',
        'Device preview.\nDevices are not scanned or paired.',
      ),
      'power' => (
        Icons.battery_charging_full_rounded,
        'Power that fits your day',
        'Power and battery integration is not implemented',
      ),
      'storage' => (
        Icons.storage_rounded,
        'Room for what matters',
        'Sample capacities.\nFiles are not scanned or cleaned.',
      ),
      'update' => (
        Icons.security_update_good_rounded,
        'Keep your system fresh',
        'Update preview.\nUpdates are not downloaded or installed.',
      ),
      _ => (Icons.settings_outlined, 'Settings preview', 'Not implemented'),
    };
    return SettingsSurface(
      child: Row(
        children: [
          Container(
            padding: const .all(18),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: .circular(24),
            ),
            child: Icon(icon, size: 38, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisplayPreview extends StatelessWidget {
  const _DisplayPreview();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsSurface(
      child: Column(
        children: [
          const Align(
            alignment: .centerLeft,
            child: Text('Display arrangement preview'),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: FittedBox(
              child: Row(
                crossAxisAlignment: .end,
                children: [
                  _Monitor(
                    number: '1',
                    width: 230,
                    height: 140,
                    color: colors.primaryContainer,
                  ),
                  const SizedBox(width: 14),
                  _Monitor(
                    number: '2',
                    width: 165,
                    height: 110,
                    color: colors.secondaryContainer,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: .center,
            children: [
              OutlinedButton(onPressed: null, child: Text('Identify')),
              OutlinedButton(onPressed: null, child: Text('Detect')),
              Text(
                'Displays have not been detected; arrangement is not draggable',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Monitor extends StatelessWidget {
  const _Monitor({
    required this.number,
    required this.width,
    required this.height,
    required this.color,
  });
  final String number;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: .circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 5,
          ),
        ),
        child: Center(
          child: Text(number, style: Theme.of(context).textTheme.displaySmall),
        ),
      ),
      Container(
        width: 10,
        height: 12,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      Container(
        width: width / 3,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: .circular(3),
        ),
      ),
    ],
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text(
            'A desktop of your own',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Container(
            height: 156,
            clipBehavior: .antiAlias,
            decoration: BoxDecoration(
              borderRadius: .circular(20),
              gradient: LinearGradient(
                begin: .topLeft,
                end: .bottomRight,
                colors: [colors.tertiaryContainer, colors.primaryContainer],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -36,
                  top: -65,
                  child: Container(
                    width: 235,
                    height: 235,
                    decoration: BoxDecoration(
                      shape: .circle,
                      color: colors.primary.withValues(alpha: .12),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  top: 24,
                  child: Container(
                    width: 125,
                    height: 83,
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: .85),
                      borderRadius: .circular(16),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.primary,
                      size: 34,
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 16,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: .7),
                      borderRadius: .circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in [
                colors.primary,
                colors.tertiary,
                colors.secondary,
                colors.outline,
              ])
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: color, shape: .circle),
                ),
              Text(
                'Theme preview. It cannot be applied yet.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
