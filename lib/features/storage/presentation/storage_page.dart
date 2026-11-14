import 'dart:convert';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../../applications/presentation/application_metadata.dart';
import '../application/storage_controller.dart';
import 'storage_widgets.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({
    super.key,
    required this.controller,
    required this.onPage,
  });
  final StorageController controller;
  final ValueChanged<String> onPage;
  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final s = c.storage;
      final drives = (s['drives'] as List?)?.cast<Map>();
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          if (c.errorMessage case final error?)
            SettingsErrorCard(
              message: error,
              onRetry: c.busy ? null : c.reload,
            ),
          _UsageCard(controller: c, onPage: widget.onPage),
          const SizedBox(height: 12),
          _CleanupLink(
            bytes: s['reclaimable_bytes'] as num?,
            onTap: () => widget.onPage('cleanup'),
          ),
          const SettingsSectionTitle('Disks and volumes'),
          if (s['disks_error'] case final String error)
            SettingsErrorCard(
              message: error,
              onRetry: c.busy ? null : () => c.change('storage.scan', {}),
            ),
          if (drives == null)
            const LinearProgressIndicator()
          else if (drives.isEmpty && s['disks_error'] == null)
            const SettingsSurface(child: Text('No drives reported by UDisks2'))
          else
            for (final drive in drives) ...[
              _DriveCard(
                key: ValueKey(drive['id']),
                drive: drive,
                controller: c,
              ),
              const SizedBox(height: 12),
            ],
        ],
      );
    },
  );
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.controller, required this.onPage});
  final StorageController controller;
  final ValueChanged<String> onPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    final usage = controller.storage['usage'] as Map? ?? {};
    final volume = usage['volume'] as Map?;
    final scanning = usage['scanning'] == true;
    final palette = storageColors(theme.colorScheme);
    // Colors follow the stable category order so they do not jump after a rescan.
    final categories = (usage['categories'] as List? ?? []).cast<Map>();
    final colorOf = {
      for (var i = 0; i < categories.length; i++)
        categories[i]['id']: palette[i % palette.length],
    };
    final shown =
        categories.where((c) => (c['bytes'] as num) >= 1024 * 1024).toList()
          ..sort((a, b) => (b['bytes'] as num).compareTo(a['bytes'] as num));
    final total = volume?['total'] as num? ?? 0;
    final used = volume?['used'] as num? ?? 0;
    final free = volume?['free'] as num? ?? 0;
    final mount = volume?['mount_point'] as String?;

    VoidCallback? open(Map category) => category['id'] == 'system'
        ? () => onPage('installed')
        : category['path'] is String && !controller.busy
        ? () => controller.change('storage.open', {'path': category['path']})
        : null;

    return SettingsSurface(
      padding: const .all(24),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            spacing: 16,
            children: [
              const IconBadge(Icons.storage_rounded),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      mount == null
                          ? 'Storage'
                          : mount == '/'
                          ? 'System drive'
                          : mount,
                      style: theme.textTheme.titleLarge,
                    ),
                    if (volume != null)
                      Text(
                        '${volume['device']} mounted at $mount',
                        style: muted,
                      ),
                  ],
                ),
              ),
              if (!scanning)
                TextButton.icon(
                  onPressed: controller.busy
                      ? null
                      : () => controller.change('storage.scan', {}),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Scan again'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (volume == null)
            const Text('Reading volume usage…')
          else ...[
            Row(
              crossAxisAlignment: .end,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: formatBytes(used),
                          style: theme.textTheme.headlineMedium,
                        ),
                        TextSpan(
                          text: '  used',
                          style: theme.textTheme.titleMedium?.merge(muted),
                        ),
                      ],
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: .end,
                  children: [
                    Text(
                      '${formatBytes(free)} free',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      'of ${formatBytes(total)}',
                      style: theme.textTheme.bodySmall?.merge(muted),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            UsageBar(
              height: 20,
              total: math.max(total, used),
              segments: [
                for (final c in shown) (c['bytes'] as num, colorOf[c['id']]!),
              ],
            ),
            const SizedBox(height: 12),
            LegendGrid(
              children: [
                for (final c in shown)
                  StorageLegend(
                    label: c['label'] as String,
                    bytes: c['bytes'] as num,
                    total: total,
                    color: colorOf[c['id']]!,
                    onTap: open(c),
                    tooltip: c['id'] == 'system'
                        ? 'Open Installed apps'
                        : c['path'] is String
                        ? 'Open ${c['path']}'
                        : null,
                  ),
                StorageLegend(
                  label: 'Free space',
                  bytes: free,
                  total: total,
                  color: theme.colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (scanning) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Scanning ${(usage['progress'] as Map?)?['files'] ?? 0} files',
              style: muted,
            ),
          ] else if (usage['scanned_at'] case final int at)
            StorageDate(
              at: at,
              controller: controller,
              prefix: 'Scanned ',
              style: theme.textTheme.bodySmall?.merge(muted),
            ),
          if ((usage['skipped'] as num? ?? 0) > 0)
            Text(
              '${usage['skipped']} unreadable entries were skipped',
              style: theme.textTheme.bodySmall?.merge(muted),
            ),
          if (total > 0 && free < total / 10) ...[
            const SizedBox(height: 16),
            _AlmostFull(onCleanup: () => onPage('cleanup')),
          ],
        ],
      ),
    );
  }
}

class _AlmostFull extends StatelessWidget {
  const _AlmostFull({required this.onCleanup});
  final VoidCallback onCleanup;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      borderRadius: .circular(16),
      child: Padding(
        padding: const .fromLTRB(16, 8, 8, 8),
        child: SettingsRowLayout(
          left: Row(
            mainAxisSize: .min,
            spacing: 12,
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.onErrorContainer),
              Flexible(
                child: Text(
                  'Storage is almost full',
                  style: TextStyle(color: colors.onErrorContainer),
                ),
              ),
            ],
          ),
          right: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colors.onErrorContainer,
            ),
            onPressed: onCleanup,
            child: const Text('Free up space'),
          ),
        ),
      ),
    );
  }
}

class _CleanupLink extends StatelessWidget {
  const _CleanupLink({required this.bytes, required this.onTap});
  final num? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsSurface(
      padding: .zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .symmetric(horizontal: 20, vertical: 16),
          child: Row(
            spacing: 16,
            children: [
              Icon(
                Icons.cleaning_services_outlined,
                color: theme.colorScheme.primary,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  spacing: 4,
                  children: [
                    Text('Cleanup', style: theme.textTheme.bodyLarge),
                    Text(
                      bytes == null || bytes == 0
                          ? 'Free up space and clean up automatically'
                          : 'Up to ${formatBytes(bytes!)} can be freed',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

String _driveType(Map d) => switch (d['connection']) {
  'nvme' => 'NVMe SSD',
  'usb' => 'USB drive',
  'sdio' => 'SD card',
  _ when d['rotational'] == true => 'Hard disk',
  'sata' => 'SATA SSD',
  _ => 'Drive',
};

IconData _driveIcon(Map d) => d['connection'] == 'usb'
    ? Icons.usb_rounded
    : d['connection'] == 'sdio'
    ? Icons.sd_card_outlined
    : d['rotational'] == true
    ? Icons.album_outlined
    : Icons.storage_rounded;

String _fileSystem(Object? type) => switch (type) {
  'vfat' => 'FAT',
  'ntfs' => 'NTFS',
  'exfat' => 'exFAT',
  'btrfs' => 'Btrfs',
  'xfs' => 'XFS',
  'swap' => 'Swap',
  'crypto_LUKS' => 'LUKS',
  final String t when t.isNotEmpty => t,
  _ => 'Unknown',
};

String _volumeName(Map v) {
  final label = v['label'] as String? ?? '';
  if (label.isNotEmpty) return label;
  final mounts = (v['mount_points'] as List).cast<String>();
  if (mounts.contains('/')) return 'System';
  return (v['device'] as String).split('/').last;
}

class _DriveCard extends StatefulWidget {
  const _DriveCard({super.key, required this.drive, required this.controller});
  final Map drive;
  final StorageController controller;
  @override
  State<_DriveCard> createState() => _DriveCardState();
}

class _DriveCardState extends State<_DriveCard> {
  String? _selected;

  Future<void> _rename(Map volume) async {
    final label = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(label: volume['label'] as String),
    );
    if (label != null) {
      await widget.controller.change('storage.label', {
        'volume': volume['id'],
        'label': label,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = widget.drive;
    final volumes = (d['volumes'] as List).cast<Map>().toList()
      ..sort((a, b) => (a['offset'] as num).compareTo(b['offset'] as num));
    final palette = storageColors(theme.colorScheme);
    final colorOf = {
      for (var i = 0; i < volumes.length; i++)
        volumes[i]['id']: palette[i % palette.length],
    };
    final selected =
        volumes.where((v) => v['id'] == _selected).firstOrNull ??
        volumes
            .where((v) => (v['mount_points'] as List).isNotEmpty)
            .firstOrNull ??
        volumes.firstOrNull;
    final safe = !volumes.any((v) => v['system'] == true);
    final canDetach =
        safe && (d['ejectable'] == true || d['can_power_off'] == true);
    return SettingsSurface(
      padding: const .all(24),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Row(
            spacing: 16,
            children: [
              IconBadge(_driveIcon(d)),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      '${d['vendor'] ?? ''} ${d['model'] ?? ''}'.trim(),
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      '${_driveType(d)}, ${formatBytes(d['size'] as num)}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (canDetach)
                PopupMenuButton<String>(
                  tooltip: 'Drive actions',
                  enabled: !widget.controller.busy,
                  onSelected: (action) => widget.controller.change(
                    'storage.eject',
                    {'drive': d['id'], 'action': action},
                  ),
                  itemBuilder: (_) => [
                    if (d['ejectable'] == true)
                      const PopupMenuItem(value: 'eject', child: Text('Eject')),
                    if (d['can_power_off'] == true)
                      const PopupMenuItem(
                        value: 'power-off',
                        child: Text('Power off'),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 20),
          _PartitionMap(
            drive: d,
            volumes: volumes,
            colorOf: colorOf,
            selected: selected?['id'] as String?,
            onSelect: (id) => setState(() => _selected = id),
          ),
          const SizedBox(height: 12),
          for (final v in volumes)
            _VolumeRow(
              key: ValueKey('volume-${v['id']}'),
              volume: v,
              color: colorOf[v['id']]!,
              selected: v['id'] == selected?['id'],
              onTap: () => setState(() => _selected = v['id'] as String),
            ),
          if (_layout(d, volumes)
                  .where((p) => p.volume == null)
                  .fold<num>(0, (s, p) => s + p.size)
              case final free when free > 0)
            _UnallocatedRow(bytes: free),
          if (selected != null) ...[
            const SizedBox(height: 12),
            _VolumeDetails(
              volume: selected,
              color: colorOf[selected['id']]!,
              controller: widget.controller,
              onRename: () => _rename(selected),
            ),
          ],
        ],
      ),
    );
  }
}

/// Partitions in disk order, with unallocated space as `volume: null`.
List<({Map? volume, num size})> _layout(Map drive, List<Map> volumes) {
  final size = drive['size'] as num;
  // Alignment gaps of a few MiB are noise; only real free space counts.
  final minGap = math.max(1 << 30, size / 100);
  final parts = <({Map? volume, num size})>[];
  num end = 0;
  for (final v in volumes) {
    final offset = v['offset'] as num;
    if (offset - end >= minGap) parts.add((volume: null, size: offset - end));
    parts.add((volume: v, size: v['size'] as num));
    end = math.max(end, offset + (v['size'] as num));
  }
  if (size - end >= minGap) parts.add((volume: null, size: size - end));
  return parts;
}

/// The drive as one bar: partitions in proportion, used space filled in.
class _PartitionMap extends StatelessWidget {
  const _PartitionMap({
    required this.drive,
    required this.volumes,
    required this.colorOf,
    required this.selected,
    required this.onSelect,
  });
  final Map drive;
  final List<Map> volumes;
  final Map<Object?, Color> colorOf;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final parts = _layout(drive, volumes);
    final total = parts.fold<num>(0, (sum, p) => sum + p.size);
    const gap = 3.0, minimum = 8.0;
    return SizedBox(
      key: const ValueKey('partition-map'),
      height: 36,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final spare = math.max(
            0.0,
            constraints.maxWidth - parts.length * (minimum + gap) + gap,
          );
          return Row(
            spacing: gap,
            children: [
              for (final p in parts)
                SizedBox(
                  width: minimum + (total > 0 ? spare * p.size / total : 0),
                  child: _PartitionSegment(
                    volume: p.volume,
                    size: p.size,
                    color: p.volume == null ? null : colorOf[p.volume!['id']]!,
                    selected: p.volume != null && p.volume!['id'] == selected,
                    onSelect: onSelect,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PartitionSegment extends StatelessWidget {
  const _PartitionSegment({
    required this.volume,
    required this.size,
    required this.color,
    required this.selected,
    required this.onSelect,
  });
  final Map? volume;
  final num size;
  final Color? color;
  final bool selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final v = volume;
    final usage = v?['usage'] as Map?;
    final fraction = usage != null && (usage['total'] as num) > 0
        ? ((usage['used'] as num) / (usage['total'] as num))
              .clamp(0.0, 1.0)
              .toDouble()
        : (v == null ? 0.0 : 1.0);
    final name = v == null ? 'Unallocated' : _volumeName(v);
    return Tooltip(
      message: '$name, ${formatBytes(size)}',
      child: Semantics(
        selected: selected,
        button: v != null,
        label: name,
        child: Material(
          color: v == null ? Colors.transparent : color!.withValues(alpha: .28),
          shape: RoundedRectangleBorder(
            borderRadius: .circular(8),
            side: v == null
                ? BorderSide(color: colors.outlineVariant)
                : selected
                ? BorderSide(color: colors.onSurface, width: 2)
                : BorderSide.none,
          ),
          clipBehavior: .antiAlias,
          child: InkWell(
            onTap: v == null ? null : () => onSelect(v['id'] as String),
            child: FractionallySizedBox(
              alignment: .centerLeft,
              widthFactor: fraction,
              heightFactor: 1,
              child: ColoredBox(color: color ?? Colors.transparent),
            ),
          ),
        ),
      ),
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({
    super.key,
    required this.volume,
    required this.color,
    required this.selected,
    required this.onTap,
  });
  final Map volume;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mounts = (volume['mount_points'] as List).cast<String>();
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Semantics(
      selected: selected,
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: .circular(12),
        child: InkWell(
          borderRadius: .circular(12),
          onTap: onTap,
          child: Padding(
            padding: const .symmetric(horizontal: 12, vertical: 10),
            child: Row(
              spacing: 12,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(color: color, shape: .circle),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _volumeName(volume),
                    style: theme.textTheme.bodyLarge,
                    overflow: .ellipsis,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(_fileSystem(volume['fs_type']), style: muted),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    mounts.isEmpty ? 'Not mounted' : mounts.join(', '),
                    style: muted,
                    overflow: .ellipsis,
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Text(
                    formatBytes(volume['size'] as num),
                    textAlign: .end,
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

class _UnallocatedRow extends StatelessWidget {
  const _UnallocatedRow({required this.bytes});
  final num bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Padding(
      padding: const .symmetric(horizontal: 12, vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: .circle,
              border: Border.all(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(child: Text('Unallocated space', style: muted)),
          Text(formatBytes(bytes), style: muted),
        ],
      ),
    );
  }
}

class _VolumeDetails extends StatelessWidget {
  const _VolumeDetails({
    required this.volume,
    required this.color,
    required this.controller,
    required this.onRename,
  });
  final Map volume;
  final Color color;
  final StorageController controller;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mounts = (volume['mount_points'] as List).cast<String>();
    final usage = volume['usage'] as Map?;
    final busy = controller.busy;
    final label = volume['label'] as String? ?? '';
    return Material(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: .circular(16),
      child: Padding(
        padding: const .all(16),
        child: Column(
          crossAxisAlignment: .stretch,
          children: [
            if (usage != null) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatBytes(usage['used'] as num)} used',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${formatBytes(usage['free'] as num)} free',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              UsageBar(
                height: 8,
                total: usage['total'] as num,
                segments: [(usage['used'] as num, color)],
              ),
              const SizedBox(height: 8),
            ],
            LegendGrid(
              minWidth: 180,
              children: [
                PropertyField(
                  label: 'Label',
                  value: label.isEmpty ? 'Not set' : label,
                ),
                PropertyField(
                  label: 'File system',
                  value: _fileSystem(volume['fs_type']),
                ),
                PropertyField(
                  label: 'Device',
                  value: volume['device'] as String,
                ),
                PropertyField(
                  label: 'Mount point',
                  value: mounts.isEmpty ? 'Not mounted' : mounts.join('\n'),
                ),
                PropertyField(
                  label: 'Size',
                  value: formatBytes(volume['size'] as num),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (mounts.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => controller.change('storage.open', {
                            'path': mounts.first,
                          }),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open'),
                  ),
                if (volume['can_mount'] == true)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => controller.change('storage.mount', {
                            'volume': volume['id'],
                            'action': 'mount',
                          }),
                    icon: const Icon(Icons.drive_folder_upload_outlined),
                    label: const Text('Mount'),
                  ),
                if (volume['can_unmount'] == true)
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => controller.change('storage.mount', {
                            'volume': volume['id'],
                            'action': 'unmount',
                          }),
                    icon: const Icon(Icons.eject_rounded),
                    label: const Text('Unmount'),
                  ),
                if (volume['can_rename'] == true)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onRename,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rename'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.label});
  final String label;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.label);
  String? get error =>
      utf8.encode(_text.text).length > 255 ||
          _text.text.runes.any(
            (c) => c < 32 || c == 127 || (c >= 128 && c <= 159) || c == 47,
          )
      ? 'Use at most 255 bytes, without / or control characters'
      : null;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename volume'),
    content: SizedBox(
      width: 400,
      child: TextField(
        controller: _text,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Label', errorText: error),
        onChanged: (_) => setState(() {}),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: error == null
            ? () => Navigator.pop(context, _text.text)
            : null,
        child: const Text('Rename'),
      ),
    ],
  );
}
