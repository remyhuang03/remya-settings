import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';

import '../domain/settings_catalog.dart';
import 'settings_widgets.dart';

enum SettingsCategoryGroup {
  connections(['network', 'devices'], .connections),
  personalization(['sound', 'appearance'], .personalization),
  system(['system', 'power', 'apps', 'remya-apps', 'ai', 'update'], .system),
  privacy(['accounts', 'privacy'], .privacy),
  preferences(['time', 'accessibility'], .preferences);

  const SettingsCategoryGroup(this.ids, this.category);
  final List<String> ids;
  final RemyaSettingsCategory category;

  String get title => category.title;

  List<SettingsCategory> categories(SettingsCatalog catalog) => [
    for (final id in ids)
      if (catalog.categories.any((category) => category.id == id))
        catalog.category(id),
  ];
}

class SettingsCategoryIcon extends StatelessWidget {
  const SettingsCategoryIcon({
    super.key,
    required this.category,
    this.size = 44,
  });
  final SettingsCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final group = SettingsCategoryGroup.values.firstWhere(
      (g) => g.ids.contains(category.id),
    );
    return RemyaSidebarIcon(
      categoryIcon(category.icon),
      size: size,
      category: group.category,
    );
  }
}
