import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../../settings/presentation/settings_list.dart';
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

class FontsPage extends StatefulWidget {
  const FontsPage({
    super.key,
    required this.page,
    required this.controller,
    this.catalog,
    this.client,
    this.pickFiles = _pickWithDialog,
  });
  final SettingsPageSpec page;
  final FontsController controller;
  final SettingsCatalog? catalog;
  final SettingsClient? client;
  final FontFilePicker pickFiles;

  @override
  State<FontsPage> createState() => _FontsPageState();
}

class _FontsPageState extends State<FontsPage> {
  String _query = '';
  late final _desktop = widget.client == null
      ? null
      : (FeatureOptionsController(widget.client!, feature: 'desktop')
          ..reload());

  @override
  void initState() {
    super.initState();
    // The list is read only here and when the service reports a font change.
    widget.controller.reload();
  }

  @override
  void dispose() {
    _desktop?.dispose();
    super.dispose();
  }

  SettingSpec _setting(String id) =>
      widget.page.controls.firstWhere((setting) => setting.id == id);

  Future<void> _install() async {
    final paths = await widget.pickFiles();
    if (paths.isNotEmpty) await widget.controller.install(paths);
  }

  Widget _compositorFontRow(
    SettingSpec setting,
    FeatureOptionsController? desktop,
  ) {
    final value = desktop?.option(fontsCompositorFamilySettingId) as String?;
    final enabled = desktop != null && desktop.canChange;
    final options = <String>{
      'Sans',
      'Serif',
      'Monospace',
      ?value,
      for (final family in widget.controller.families) family.name,
    }.where((s) => s.isNotEmpty).toList();
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
          Text(setting.reason, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      control: DropdownMenu<String>(
        key: ValueKey('${setting.id}-$value-${options.length}'),
        width: 260,
        menuHeight: 320,
        enabled: enabled,
        initialSelection: value != null && options.contains(value)
            ? value
            : null,
        hintText: value ?? 'Unknown',
        dropdownMenuEntries: [
          for (final family in options)
            DropdownMenuEntry(value: family, label: family),
        ],
        onSelected: (next) {
          if (next != null && next != value) {
            desktop?.set(fontsCompositorFamilySettingId, next);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final desktop = _desktop;
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, ?desktop]),
      builder: (context, _) {
        final controller = widget.controller;
        final matches = controller.matching(_query).toList();
        final indices = {
          for (var i = 0; i < matches.length; i++)
            ValueKey('font-${matches[i].name}'): i,
        };
        return Column(
          crossAxisAlignment: .stretch,
          children: [
            if (controller.isBusy || (desktop?.isBusy ?? false))
              const LinearProgressIndicator(),
            if (controller.errorMessage case final error?)
              Padding(
                padding: const .only(bottom: 12),
                child: Text(
                  error,
                  key: const ValueKey('fonts-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (desktop?.errorMessage case final error?)
              SettingsErrorCard(message: error, onRetry: desktop!.reload),
            if (desktop != null && desktop.isLoaded) ...[
              if (desktop.writeBlocked case final reason?)
                SettingsErrorCard(message: reason, onRetry: desktop.reload),
              if (desktop.hasConflict && widget.catalog != null)
                InputConflictCard(
                  controls: widget.catalog!.pages.expand((p) => p.controls),
                  controller: desktop,
                  title: 'Desktop settings differ from saved Settings',
                ),
            ],
            SettingsList(
              title: controller.loaded
                  ? '${matches.length} font families'
                  : 'Reading fonts…',
              actions: [
                SizedBox(
                  width: 232,
                  child: TextField(
                    key: const ValueKey('fonts-search'),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Search fonts',
                      prefixIcon: Icon(Icons.search_rounded, size: 20),
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Tooltip(
                  message: _setting(fontsInstallSettingId).reason,
                  child: FilledButton.icon(
                    key: const ValueKey('fonts-install'),
                    onPressed: controller.isBusy ? null : _install,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Install fonts'),
                  ),
                ),
              ],
              empty: Text(
                controller.loaded ? 'No fonts found' : 'Reading fonts…',
              ),
              itemExtent: _rowHeight,
              itemCount: matches.length,
              findChildIndexCallback: (key) => indices[key],
              itemBuilder: (context, index) => _FamilyRow(
                key: ValueKey('font-${matches[index].name}'),
                family: matches[index],
                onTap: () => _showDetails(context, matches[index]),
              ),
            ),
            AdvancedSection(
              storageKey: const PageStorageKey('fonts-advanced'),
              child: KeyedSubtree(
                key: const PageStorageKey('fonts-advanced-body'),
                child: settingsRows([
                  _compositorFontRow(
                    _setting(fontsCompositorFamilySettingId),
                    desktop,
                  ),
                  for (final setting in widget.page.controls.where(
                    (s) => s.availability != .available,
                  ))
                    SettingControlTile(setting),
                ]),
              ),
            ),
          ],
        );
      },
    );
  }

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
  const _FamilyRow({super.key, required this.family, required this.onTap});
  final FontFamily family;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: .transparency,
      child: InkWell(
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

/// Font matching and text layout are expensive; only load visible previews after scrolling settles.
class _FontPreview extends StatefulWidget {
  const _FontPreview(this.family);
  final String family;

  @override
  State<_FontPreview> createState() => _FontPreviewState();
}

class _FontPreviewState extends State<_FontPreview> {
  ScrollPosition? _position;
  Timer? _settle;
  bool _load = false;

  @override
  void didUpdateWidget(covariant _FontPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.of(context).position;
    if (position == _position) return;
    _detach();
    _position = position;
    position.addListener(_schedule);
    position.isScrollingNotifier.addListener(_schedule);
    _schedule();
  }

  void _detach() {
    _settle?.cancel();
    _position?.removeListener(_schedule);
    _position?.isScrollingNotifier.removeListener(_schedule);
  }

  void _schedule() {
    _settle?.cancel();
    if (_load || _position!.isScrollingNotifier.value) return;
    _settle = Timer(const Duration(milliseconds: 250), () {
      final position = _position!;
      final render = context.findRenderObject();
      final viewport = RenderAbstractViewport.maybeOf(render);
      if (render == null ||
          viewport == null ||
          position.isScrollingNotifier.value) {
        return;
      }
      final top = viewport.getOffsetToReveal(render, 0).offset;
      if (top >= position.pixels + position.viewportDimension ||
          top + render.paintBounds.height <= position.pixels) {
        return;
      }
      setState(() => _load = true);
    });
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_load
      ? const SizedBox(height: 25.2)
      : Text(
          _sample,
          maxLines: 1,
          overflow: .ellipsis,
          strutStyle: const StrutStyle(
            fontSize: 18,
            height: 1.4,
            forceStrutHeight: true,
          ),
          style: TextStyle(fontFamily: widget.family, fontSize: 18),
        );
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
