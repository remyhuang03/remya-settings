import 'package:file_selector/file_selector.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/fonts_controller.dart';

const _fontTypes = XTypeGroup(
  label: 'Fonts',
  extensions: ['ttf', 'otf', 'ttc', 'otc', 'woff', 'woff2'],
);
const _rowHeight = 76.0;
const _sample = 'The quick brown fox jumps over the lazy dog';

typedef FontFilePicker = Future<List<String>> Function();

Future<List<String>> _pickWithDialog() async => [
  for (final file in await openFiles(acceptedTypeGroups: [_fontTypes]))
    file.path,
];

/// A sliver: rows build lazily because each preview loads a whole font file.
class FontsPage extends StatefulWidget {
  const FontsPage({
    super.key,
    required this.page,
    required this.controller,
    this.pickFiles = _pickWithDialog,
  });
  final SettingsPageSpec page;
  final FontsController controller;
  final FontFilePicker pickFiles;

  @override
  State<FontsPage> createState() => _FontsPageState();
}

class _FontsPageState extends State<FontsPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // The list is read only here and when the service reports a font change.
    widget.controller.reload();
  }

  SettingSpec _setting(String id) =>
      widget.page.controls.firstWhere((setting) => setting.id == id);

  Future<void> _install() async {
    final paths = await widget.pickFiles();
    if (paths.isNotEmpty) await widget.controller.install(paths);
  }

  Widget _label(BuildContext context, SettingSpec setting) => Column(
    crossAxisAlignment: .start,
    children: [
      Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 6),
      Text(setting.reason, style: Theme.of(context).textTheme.bodySmall),
    ],
  );

  Widget _controls(BuildContext context, List<FontFamily> matches) {
    final controller = widget.controller;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              SettingRow(
                id: fontsSearchSettingId,
                label: _label(context, _setting(fontsSearchSettingId)),
                control: SizedBox(
                  width: 232,
                  child: TextField(
                    key: const ValueKey('fonts-search'),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search fonts',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                      border: OutlineInputBorder(
                        borderRadius: .all(.circular(14)),
                      ),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
              ),
              const Divider(height: 1, indent: 20, endIndent: 20),
              SettingRow(
                id: fontsInstallSettingId,
                label: _label(context, _setting(fontsInstallSettingId)),
                control: FilledButton.icon(
                  key: const ValueKey('fonts-install'),
                  onPressed: controller.isBusy ? null : _install,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Browse'),
                ),
              ),
            ],
          ),
        ),
        if (controller.isBusy) const LinearProgressIndicator(),
        if (controller.errorMessage case final error?)
          Padding(
            padding: const .only(top: 12),
            child: Text(
              error,
              key: const ValueKey('fonts-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const .only(top: 28, bottom: 12),
          child: Text(
            controller.loaded
                ? '${matches.length} font families'
                : 'Reading fonts…',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final matches = widget.controller.matching(_query).toList();
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: _controls(context, matches)),
          if (matches.isEmpty && widget.controller.loaded)
            const SliverToBoxAdapter(
              child: SettingsSurface(child: Text('No fonts found')),
            ),
          DecoratedSliver(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: .circular(24),
            ),
            sliver: SliverFixedExtentList.builder(
              itemExtent: _rowHeight,
              itemCount: matches.length,
              itemBuilder: (context, index) => _FamilyRow(
                key: ValueKey('font-${matches[index].name}'),
                family: matches[index],
                first: index == 0,
                last: index == matches.length - 1,
                onTap: () => _showDetails(context, matches[index]),
              ),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _showDetails(BuildContext context, FontFamily family) =>
      showDialog<void>(
        context: context,
        builder: (_) => _DetailsDialog(
          family: family,
          reason: _setting(fontsUninstallSettingId).reason,
          controller: widget.controller,
        ),
      );
}

class _FamilyRow extends StatelessWidget {
  const _FamilyRow({
    super.key,
    required this.family,
    required this.first,
    required this.last,
    required this.onTap,
  });
  final FontFamily family;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.vertical(
      top: .circular(first ? 24 : 0),
      bottom: .circular(last ? 24 : 0),
    );
    return Material(
      type: .transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const .symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: .center,
                  crossAxisAlignment: .start,
                  children: [
                    Text(family.name, maxLines: 1, overflow: .ellipsis),
                    _FontPreview(family.name),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the sample in its font once the row is settled: a fast fling would otherwise
/// load every font file it passes. The fixed strut keeps tall fonts inside the row.
class _FontPreview extends StatefulWidget {
  const _FontPreview(this.family);
  final String family;

  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
  bool _load = false;

  void _check() {
    if (!mounted) return;
    if (Scrollable.recommendDeferredLoadingForContext(context)) {
      SchedulerBinding.instance.scheduleFrameCallback((_) => _check());
    } else {
      setState(() => _load = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_load) {
      if (!Scrollable.recommendDeferredLoadingForContext(context)) {
        _load = true;
      } else {
        SchedulerBinding.instance.scheduleFrameCallback((_) => _check());
      }
    }
    return Text(
      _sample,
      maxLines: 1,
      overflow: .ellipsis,
      strutStyle: const StrutStyle(
        fontSize: 18,
        height: 1.4,
        forceStrutHeight: true,
      ),
      style: TextStyle(fontFamily: _load ? widget.family : null, fontSize: 18),
    );
  }
}

class _DetailsDialog extends StatelessWidget {
  const _DetailsDialog({
    required this.family,
    required this.reason,
    required this.controller,
  });
  final FontFamily family;
  final String reason;
  final FontsController controller;

  Future<void> _uninstall(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Uninstall ${family.name}?'),
        content: Text(
          'This deletes ${family.userFiles} file(s) from your font directory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            key: const ValueKey('fonts-uninstall-confirm'),
            style: destructiveFilledButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Uninstall'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    navigator.pop();
    await controller.uninstall(family.name);
  }

  Widget _field(BuildContext context, String label, String value) => Padding(
    padding: const .only(top: 12),
    child: Column(
      crossAxisAlignment: .start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(family.name),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(
              _sample,
              style: TextStyle(fontFamily: family.name, fontSize: 28),
            ),
            _field(context, 'Styles', family.styles.join(', ')),
            _field(context, 'Formats', family.formats.join(', ')),
            _field(context, 'Files', family.files.join('\n')),
            if (!family.removable) ...[
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 18),
                  SizedBox(width: 8),
                  Expanded(child: Text('Installed for the whole system')),
                ],
              ),
            ] else if (family.systemFiles > 0) ...[
              const SizedBox(height: 16),
              Text(reason),
            ],
          ],
        ),
      ),
    ),
    actions: [
      if (family.removable)
        TextButton.icon(
          key: const ValueKey('fonts-uninstall'),
          style: destructiveTextButtonStyle(context),
          onPressed: controller.isBusy ? null : () => _uninstall(context),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('Uninstall'),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
