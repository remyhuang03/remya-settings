import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import 'theme_pack_widgets.dart';

/// Icons that show a theme's character at a glance.
const _sampleIcons = [
  'folder',
  'user-home',
  'text-x-generic',
  'image-x-generic',
  'utilities-terminal',
];

/// Colors and themes, with the icon theme and theme packs from the service.
class ThemesPage extends StatefulWidget {
  const ThemesPage({
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
  State<ThemesPage> createState() => _ThemesPageState();
}

class _ThemesPageState extends State<ThemesPage> {
  late final _packs = FeatureOptionsController(widget.client, feature: 'themes')
    ..reload();

  @override
  void dispose() {
    _packs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _packs,
    builder: (context, _) {
      final icon = _packs.option(iconThemeId) as String?;
      return SettingsDetail(
        catalog: widget.catalog,
        page: widget.page,
        onPage: widget.onPage,
        client: widget.client,
        leading: [
          const SizedBox(height: 12),
          if (_packs.errorMessage case final error?)
            SettingsErrorCard(message: error, onRetry: _packs.reload),
          if (_packs.hasConflict)
            InputConflictCard(
              controls: widget.catalog.pages.expand((p) => p.controls),
              controller: _packs,
              title: 'Cursor and icon themes differ from saved Settings',
            ),
        ],
        isVisible: (setting) => switch (setting.id) {
          iconRemoveId => _packs.userThemes.isNotEmpty,
          _ => true,
        },
        controlBuilder: (setting) => switch (setting.id) {
          iconThemeId when !_packs.isLoaded => const RemyaLoadingBar(),
          iconThemeId => ThemeGalleryRow(
            setting: setting,
            packs: _packs.iconThemes,
            selected: icon,
            enabled: _packs.canChange,
            onSelected: (id) => _packs.set(iconThemeId, id),
            preview: (pack) => Row(
              spacing: 6,
              children: [
                for (final name in _sampleIcons)
                  ThemeIcon(theme: pack['id'] as String, name: name, size: 26),
              ],
            ),
          ),
          iconInstallId => ThemeInstallRow(
            setting: setting,
            controller: _packs,
          ),
          iconRemoveId => ThemeRemoveRow(
            setting: setting,
            controller: _packs,
            inUse: {?icon, ?(_packs.option(cursorThemeId) as String?)},
          ),
          _ => null,
        },
      );
    },
  );
}
