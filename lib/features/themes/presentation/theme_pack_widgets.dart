import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';

/// One installed theme pack as the service lists it.
typedef ThemePack = Map<String, dynamic>;

extension ThemePacksState on FeatureOptionsController {
  List<ThemePack> get cursorThemes => list('cursor_themes');
  List<ThemePack> get iconThemes => list('icon_themes');

  /// Packs in the user's own folder, which Settings may remove.
  List<ThemePack> get userThemes => {
    for (final pack in [...cursorThemes, ...iconThemes])
      if (pack['user'] == true) pack['id'] as String: pack,
  }.values.toList();
}

/// Cursor previews by theme and size; each is read from the service once.
class CursorPreviews {
  CursorPreviews(this.client);
  final SettingsClient client;
  final _previews = <String, Future<Map<String, dynamic>?>>{};

  Future<Map<String, dynamic>?> get(String theme, int size) =>
      _previews.putIfAbsent('$theme@$size', () async {
        try {
          return await client.cursorPreview(theme, size);
        } catch (error) {
          debugPrint('cursor preview $theme: $error');
          return null;
        }
      });
}

/// Cursor images of [theme] in [roles], each drawn [size] pixels tall.
class CursorImages extends StatelessWidget {
  const CursorImages({
    super.key,
    required this.previews,
    required this.theme,
    required this.size,
    this.roles = const ['pointer', 'text', 'link', 'busy'],
    this.spacing = 12,
  });
  final CursorPreviews previews;
  final String theme;
  final double size;
  final List<String> roles;
  final double spacing;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
    // Ask for the nominal size at or above the drawn one, for sharp images.
    future: previews.get(theme, size.round()),
    builder: (context, snapshot) {
      final images = {
        for (final image
            in (snapshot.data?['images'] as List? ?? []).cast<Map>())
          image['role'] as String: image,
      };
      if (snapshot.connectionState != .done) {
        return SizedBox(height: size);
      }
      if (images.isEmpty) {
        return SizedBox(
          height: size,
          child: Icon(
            Icons.mouse_outlined,
            size: size * 0.8,
            semanticLabel: 'No preview for this theme format',
          ),
        );
      }
      return Row(
        mainAxisSize: .min,
        spacing: spacing,
        children: [
          for (final role in roles)
            if (images[role] case final image?)
              Semantics(
                label: '$role cursor',
                image: true,
                child: Image.memory(
                  base64Decode(image['png'] as String),
                  width: size,
                  height: size,
                  fit: .contain,
                  filterQuality: .medium,
                  gaplessPlayback: true,
                ),
              ),
        ],
      );
    },
  );
}

/// Icons from a given installed icon theme, rendered by the GTK runner.
class ThemeIcon extends StatelessWidget {
  const ThemeIcon({
    super.key,
    required this.theme,
    required this.name,
    this.size = 32,
  });
  final String theme;
  final String name;
  final double size;
  static final _icons = <String, Future<Uint8List?>>{};
  static const _channel = MethodChannel('top.remya.paths');

  static Future<Uint8List?> _load(String theme, String name, int size) async {
    try {
      return await _channel.invokeMethod<Uint8List>('themeIcon', [
        theme,
        name,
        size,
      ]);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixels = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return SizedBox.square(
      dimension: size,
      child: FutureBuilder<Uint8List?>(
        future: _icons.putIfAbsent(
          '$theme/$name@$pixels',
          () => _load(theme, name, pixels),
        ),
        builder: (context, snapshot) => snapshot.data == null
            ? const SizedBox.shrink()
            : Image.memory(snapshot.data!, width: size, height: size),
      ),
    );
  }
}

/// A selectable card in a theme gallery.
class ThemeCard extends StatelessWidget {
  const ThemeCard({
    super.key,
    required this.pack,
    required this.selected,
    required this.onTap,
    required this.preview,
  });
  final ThemePack pack;
  final bool selected;
  final VoidCallback? onTap;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      label: pack['name'] as String,
      child: Material(
        color: selected
            ? colors.secondaryContainer
            : colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(16),
          side: BorderSide(
            color: selected ? colors.primary : colors.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: .antiAlias,
        child: InkWell(
          key: ValueKey('theme-${pack['id']}'),
          onTap: onTap,
          child: SizedBox(
            width: 184,
            child: Padding(
              padding: const .all(12),
              child: Column(
                crossAxisAlignment: .start,
                spacing: 10,
                children: [
                  SizedBox(
                    height: 40,
                    child: Align(alignment: .centerLeft, child: preview),
                  ),
                  Row(
                    spacing: 4,
                    children: [
                      if (selected)
                        Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: colors.onSecondaryContainer,
                        ),
                      Expanded(
                        child: Text(
                          pack['name'] as String,
                          style: text.labelLarge,
                          maxLines: 2,
                          overflow: .ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (pack['user'] == true)
                    Text(
                      'Added by you',
                      style: text.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled gallery row; warns when the selected theme is not installed.
class ThemeGalleryRow extends StatelessWidget {
  const ThemeGalleryRow({
    super.key,
    required this.setting,
    required this.packs,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.preview,
  });
  final SettingSpec setting;
  final List<ThemePack> packs;
  final String? selected;
  final bool enabled;
  final ValueChanged<String> onSelected;
  final Widget Function(ThemePack) preview;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final missing =
        selected != null && !packs.any((pack) => pack['id'] == selected);
    return Padding(
      key: ValueKey(setting.id),
      padding: const .symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: .stretch,
        spacing: 12,
        children: [
          Text(setting.title, style: text.bodyLarge),
          if (missing)
            Row(
              spacing: 8,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                Expanded(
                  child: Text(
                    '“$selected” is selected but is not installed in a theme '
                    'folder. Choose an installed theme.',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          if (packs.isEmpty)
            Text('No themes are installed.', style: text.bodySmall)
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final pack in packs)
                  ThemeCard(
                    pack: pack,
                    selected: pack['id'] == selected,
                    onTap: enabled && pack['id'] != selected
                        ? () => onSelected(pack['id'] as String)
                        : null,
                    preview: preview(pack),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

const _archives = XTypeGroup(
  label: 'Theme archives',
  extensions: ['tar', 'gz', 'tgz', 'xz', 'txz', 'bz2', 'tbz', 'zst', 'zip'],
);

/// Picks a theme folder (true) or archive (false); returns null when cancelled.
typedef ThemeSourcePicker = Future<String?> Function(bool folder);

Future<String?> pickThemeSource(bool folder) async => folder
    ? await getDirectoryPath(confirmButtonText: 'Add theme')
    : (await openFile(acceptedTypeGroups: [_archives]))?.path;

/// Adds the themes in a chosen folder or archive to the user's icon folder.
class ThemeInstallRow extends StatelessWidget {
  const ThemeInstallRow({
    super.key,
    required this.setting,
    required this.controller,
    this.pick = pickThemeSource,
  });
  final SettingSpec setting;
  final FeatureOptionsController controller;
  final ThemeSourcePicker pick;

  Future<void> _install(BuildContext context, bool folder) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final source = await pick(folder);
    if (source == null) return;
    if (await controller.set(setting.id, source)) {
      final added = (controller.state['installed'] as List? ?? []).join(', ');
      messenger?.showSnackBar(SnackBar(content: Text('Added $added')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = controller.isLoaded && !controller.isBusy;
    final folder = controller.state['user_folder'] as String?;
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            'Choose a downloaded theme folder or archive. It is copied to '
            '${folder ?? 'your icon folder'}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            key: ValueKey('${setting.id}-folder'),
            onPressed: enabled ? () => _install(context, true) : null,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Folder'),
          ),
          OutlinedButton.icon(
            key: ValueKey('${setting.id}-archive'),
            onPressed: enabled ? () => _install(context, false) : null,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive'),
          ),
        ],
      ),
    );
  }
}

/// Removes a theme the user added; shown only while there is one.
class ThemeRemoveRow extends StatefulWidget {
  const ThemeRemoveRow({
    super.key,
    required this.setting,
    required this.controller,
    required this.inUse,
  });
  final SettingSpec setting;
  final FeatureOptionsController controller;

  /// Themes selected now, which cannot be removed.
  final Set<String> inUse;

  @override
  State<ThemeRemoveRow> createState() => _ThemeRemoveRowState();
}

class _ThemeRemoveRowState extends State<ThemeRemoveRow> {
  String? _choice;

  Future<void> _remove(ThemePack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${pack['name']}?'),
        content: Text(
          'The theme folder ${pack['path']} is deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (await widget.controller.set(widget.setting.id, pack['id'] as String)) {
      setState(() => _choice = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final packs = widget.controller.userThemes;
    final choice = packs.where((p) => p['id'] == _choice).firstOrNull;
    final enabled = widget.controller.isLoaded && !widget.controller.isBusy;
    final blocked = choice != null && widget.inUse.contains(choice['id']);
    return SettingRow(
      id: widget.setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 4,
        children: [
          Text(
            widget.setting.title,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (blocked)
            Text(
              'Choose another theme before removing this one.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      control: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: .center,
        children: [
          DropdownMenu<String>(
            key: ValueKey('${widget.setting.id}-choice'),
            width: 220,
            enabled: enabled,
            hintText: 'Theme',
            initialSelection: choice?['id'] as String?,
            dropdownMenuEntries: [
              for (final pack in packs)
                DropdownMenuEntry(
                  value: pack['id'] as String,
                  label: pack['name'] as String,
                ),
            ],
            onSelected: (id) => setState(() => _choice = id),
          ),
          FilledButton.tonal(
            key: ValueKey('${widget.setting.id}-button'),
            onPressed: enabled && choice != null && !blocked
                ? () => _remove(choice)
                : null,
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

/// The folders searched for themes, with the user's own folder marked.
class ThemeFoldersRow extends StatelessWidget {
  const ThemeFoldersRow({
    super.key,
    required this.setting,
    required this.controller,
  });
  final SettingSpec setting;
  final FeatureOptionsController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    // Missing system folders are noise; the user's folder is created on demand.
    final folders = controller
        .list('folders')
        .where((f) => f['exists'] == true || f['user'] == true)
        .toList();
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        spacing: 6,
        children: [
          Text(setting.title, style: text.bodyLarge),
          Text(setting.reason, style: text.bodySmall),
          for (final folder in folders)
            Row(
              spacing: 8,
              children: [
                Icon(
                  folder['user'] == true
                      ? Icons.person_outline_rounded
                      : Icons.folder_outlined,
                  size: 18,
                  color: colors.onSurfaceVariant,
                ),
                Flexible(
                  child: Text(
                    folder['path'] as String,
                    style: text.bodyMedium?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
                if (folder['user'] == true)
                  Text(
                    'Your themes',
                    style: text.labelSmall?.copyWith(color: colors.primary),
                  ),
                if (folder['icons'] != true)
                  Text('Cursors only', style: text.labelSmall),
              ],
            ),
        ],
      ),
    );
  }
}
