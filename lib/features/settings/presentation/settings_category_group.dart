import 'package:material_ui/material_ui.dart';

import '../domain/settings_catalog.dart';
import 'settings_widgets.dart';

enum SettingsCategoryGroup {
  connections(
    'Connections',
    ['network', 'devices'],
    Color(0xffb8d8ff),
    Color(0xff12385b),
  ),
  personalization(
    'Personalization',
    ['sound', 'notifications', 'appearance'],
    Color(0xffffc4df),
    Color(0xff5b173d),
  ),
  system(
    'Device & system',
    ['system', 'power', 'apps', 'ai', 'update'],
    Color(0xffbdebbd),
    Color(0xff1b4624),
  ),
  privacy(
    'Accounts & privacy',
    ['accounts', 'privacy'],
    Color(0xffa8e8ed),
    Color(0xff004b50),
  ),
  preferences(
    'Language & accessibility',
    ['time', 'accessibility'],
    Color(0xffffdda6),
    Color(0xff593b08),
  ),
  desktop(
    'Hyprland',
    ['hyprland', 'session'],
    Color(0xffdfccff),
    Color(0xff402769),
  );

  const SettingsCategoryGroup(
    this.title,
    this.ids,
    this.background,
    this.foreground,
  );
  final String title;
  final List<String> ids;
  final Color background;
  final Color foreground;

  List<SettingsCategory> categories(SettingsCatalog catalog) => [
    for (final id in ids) catalog.category(id),
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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: group.background, shape: .circle),
      child: Icon(
        categoryIcon(category.icon),
        color: group.foreground,
        size: size * .55,
      ),
    );
  }
}
