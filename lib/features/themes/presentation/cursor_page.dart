import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import '../../settings/presentation/settings_widgets.dart';
import 'theme_pack_widgets.dart';

/// Cursor theme and size, theme packs, and when the pointer hides or moves.
class CursorPage extends StatefulWidget {
  const CursorPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
    required this.onPage,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;
  final ValueChanged<SettingsPageSpec> onPage;

  @override
  State<CursorPage> createState() => _CursorPageState();
}

class _CursorPageState extends State<CursorPage> {
  late final _packs = FeatureOptionsController(widget.client, feature: 'themes')
    ..reload();
  late final _desktop = FeatureOptionsController(
    widget.client,
    feature: 'desktop',
  )..reload();
  late final _previews = CursorPreviews(widget.client);
  final _dragging = <String, double>{};

  @override
  void dispose() {
    _packs.dispose();
    _desktop.dispose();
    super.dispose();
  }

  String? get _theme => _packs.option(cursorThemeId) as String?;
  int get _size =>
      _dragging[cursorSizeId]?.round() ??
      (_packs.option(cursorSizeId) as num? ?? 24).toInt();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_packs, _desktop]),
    builder: (context, _) {
      final controls = widget.catalog.pages.expand((p) => p.controls);
      final rows = InputRows(
        context,
        _desktop,
        _dragging,
        (id, value) => setState(
          () => value == null ? _dragging.remove(id) : _dragging[id] = value,
        ),
      );
      final text = Theme.of(context).textTheme;
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(widget.page.description, style: text.bodyLarge),
          const SizedBox(height: 12),
          for (final controller in [_packs, _desktop]) ...[
            if (controller.errorMessage case final error?)
              SettingsErrorCard(message: error, onRetry: controller.reload),
            if (controller.writeBlocked case final reason?)
              SettingsErrorCard(message: reason, onRetry: controller.reload),
          ],
          if (_packs.hasConflict)
            InputConflictCard(
              controls: controls,
              controller: _packs,
              title: 'Cursor and icon themes differ from saved Settings',
            ),
          if (_desktop.hasConflict)
            InputConflictCard(
              controls: controls,
              controller: _desktop,
              title: 'Desktop settings differ from saved Settings',
            ),
          if (!_packs.isLoaded || !_desktop.isLoaded)
            const RemyaLoadingBar()
          else ...[
            if (_theme case final theme?)
              InputHero(
                caption:
                    'Pointer, text, link and busy cursors at $_size pixels. '
                    'Open applications may keep the previous cursor until '
                    'they restart.',
                child: SizedBox(
                  height: _size + 24.0,
                  child: Center(
                    child: CursorImages(
                      key: ValueKey('cursor-hero-$theme-$_size'),
                      previews: _previews,
                      theme: theme,
                      size: _size.toDouble(),
                      spacing: 24,
                    ),
                  ),
                ),
              ),
            for (final section in widget.page.sections)
              SettingsSectionCard(
                section,
                onPageRow: (_) {},
                pageRows: const {},
                isVisible: (setting) => switch (setting.id) {
                  cursorRemoveId => _packs.userThemes.isNotEmpty,
                  _ => true,
                },
                controlBuilder: (setting) => _row(setting, rows),
              ),
            if (widget.page.children.isNotEmpty) ...[
              const SettingsSectionTitle('Related settings'),
              SettingsSurface(
                padding: .zero,
                child: Column(
                  children: [
                    for (final id in widget.page.children)
                      PageLink(
                        page: widget.catalog.page(id),
                        icon: pageIcon(
                          widget.catalog.page(id),
                          widget.catalog.category(
                            widget.catalog.page(id).category,
                          ),
                        ),
                        onTap: () => widget.onPage(widget.catalog.page(id)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ],
      );
    },
  );

  Widget _row(SettingSpec setting, InputRows rows) => switch (setting.id) {
    cursorThemeId => ThemeGalleryRow(
      setting: setting,
      packs: _packs.cursorThemes,
      selected: _theme,
      enabled: _packs.canChange,
      onSelected: (id) => _packs.set(cursorThemeId, id),
      preview: (pack) => CursorImages(
        previews: _previews,
        theme: pack['id'] as String,
        size: 32,
        roles: const ['pointer', 'text', 'link'],
        spacing: 6,
      ),
    ),
    cursorSizeId => _SizeRow(
      setting: setting,
      controller: _packs,
      previews: _previews,
      theme: _theme,
      size: _size,
      onDrag: (value) => setState(
        () => value == null
            ? _dragging.remove(cursorSizeId)
            : _dragging[cursorSizeId] = value,
      ),
    ),
    cursorInstallId => ThemeInstallRow(setting: setting, controller: _packs),
    cursorRemoveId => ThemeRemoveRow(
      setting: setting,
      controller: _packs,
      inUse: {?_theme, ?(_packs.option(iconThemeId) as String?)},
    ),
    'cursor.folders' => ThemeFoldersRow(setting: setting, controller: _packs),
    'cursor.no-warps' => rows.build(
      setting,
      subtitle: 'The pointer does not jump to a window when focus moves to it',
    ),
    'cursor.enable-hyprcursor' => rows.build(
      setting,
      subtitle: 'Uses the scalable version of themes that include one',
    ),
    'cursor.hardware' => rows.build(
      setting,
      subtitle: 'Turn off if the cursor flickers or is invisible',
    ),
    _ => rows.build(setting),
  };
}

/// Cursor size; XCursor themes offer fixed sizes, so the slider stops there.
class _SizeRow extends StatelessWidget {
  const _SizeRow({
    required this.setting,
    required this.controller,
    required this.previews,
    required this.theme,
    required this.size,
    required this.onDrag,
  });
  final SettingSpec setting;
  final FeatureOptionsController controller;
  final CursorPreviews previews;
  final String? theme;
  final int size;
  final ValueChanged<double?> onDrag;

  @override
  Widget build(BuildContext context) {
    final saved = (controller.option(cursorSizeId) as num? ?? 24).toInt();
    return FutureBuilder<Map<String, dynamic>?>(
      future: theme == null ? null : previews.get(theme!, saved),
      builder: (context, snapshot) {
        final sizes = (snapshot.data?['sizes'] as List? ?? [])
            .cast<num>()
            .map((s) => s.toDouble())
            .where((s) => s >= 8 && s <= 256)
            .toList();
        final stops = sizes.length >= 2 ? sizes : null;
        final enabled = controller.canChange;
        final Widget slider;
        if (stops != null) {
          // Positions are indexes into the theme's own sizes.
          var index = 0;
          for (var i = 0; i < stops.length; i++) {
            if ((stops[i] - size).abs() < (stops[index] - size).abs()) {
              index = i;
            }
          }
          slider = Slider(
            key: ValueKey('$cursorSizeId-slider'),
            value: index.toDouble(),
            max: (stops.length - 1).toDouble(),
            divisions: stops.length - 1,
            label: '${stops[index].round()} px',
            onChanged: enabled ? (i) => onDrag(stops[i.round()]) : null,
            onChangeEnd: enabled
                ? (i) {
                    onDrag(null);
                    controller.set(cursorSizeId, stops[i.round()].round());
                  }
                : null,
          );
        } else {
          slider = Slider(
            key: ValueKey('$cursorSizeId-slider'),
            value: size.clamp(16, 96).toDouble(),
            min: 16,
            max: 96,
            divisions: 20,
            label: '$size px',
            onChanged: enabled ? onDrag : null,
            onChangeEnd: enabled
                ? (v) {
                    onDrag(null);
                    controller.set(cursorSizeId, v.round());
                  }
                : null,
          );
        }
        final text = Theme.of(context).textTheme;
        return SettingRow(
          id: setting.id,
          label: Column(
            crossAxisAlignment: .start,
            spacing: 4,
            children: [
              Text(setting.title, style: text.bodyLarge),
              Text(
                stops == null
                    ? '$size px'
                    : stops.length > 6
                    ? '$size px. This theme has ${stops.length} sizes from '
                          '${stops.first.round()} to ${stops.last.round()} px.'
                    : '$size px. This theme provides '
                          '${stops.map((s) => s.round()).join(', ')} px.',
                style: text.bodySmall,
              ),
            ],
          ),
          control: SizedBox(width: 260, child: slider),
        );
      },
    );
  }
}
