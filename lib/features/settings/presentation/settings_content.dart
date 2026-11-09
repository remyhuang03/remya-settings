import 'package:remya_settings_client/settings_contract.dart';

import '../../system_information/presentation/system_information_page.dart';

import 'package:material_ui/material_ui.dart';

import '../../night_light/application/night_light_controller.dart';
import '../../night_light/presentation/night_light_page.dart';

import '../../background/application/background_controller.dart';
import '../../background/presentation/background_page.dart';
import '../../date_time/application/date_time_controller.dart';
import '../../date_time/presentation/date_time_settings.dart';
import '../../display/application/display_controller.dart';
import '../../display/presentation/display_settings.dart';
import '../domain/settings_catalog.dart';
import 'settings_preview.dart';
import 'settings_category_group.dart';
import 'settings_widgets.dart';

class SettingsHome extends StatelessWidget {
  const SettingsHome({
    super.key,
    required this.catalog,
    required this.onCategory,
  });
  final SettingsCatalog catalog;
  final ValueChanged<String> onCategory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final group in SettingsCategoryGroup.values) ...[
          Padding(
            padding: const .only(top: 12, bottom: 10),
            child: Text(
              group.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ClipRRect(
            key: ValueKey('home-group-${group.name}'),
            borderRadius: .circular(28),
            child: Column(
              children: [
                for (final category in group.categories(catalog)) ...[
                  if (category.id != group.ids.first) const SizedBox(height: 2),
                  _CategoryCard(
                    category: category,
                    onTap: () => onCategory(category.id),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});
  final SettingsCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: .circular(4),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .all(22),
          child: Row(
            children: [
              SettingsCategoryIcon(category: category, size: 48),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      category.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      category.description,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsDetail extends StatelessWidget {
  const SettingsDetail({
    super.key,
    required this.catalog,
    required this.page,
    required this.onPage,
    this.systemInformation,
    this.client,
    this.controlBuilder,
    this.isVisible,
    this.leading = const [],
  });
  final bool Function(SettingSpec)? isVisible;
  final SettingsCatalog catalog;

  /// Builds the rows a feature implements itself; null keeps the catalog row.
  final Widget? Function(SettingSpec)? controlBuilder;

  /// Shown above the sections, such as a configuration conflict.
  final List<Widget> leading;

  /// Reaches the service directly for pages without an app-wide controller.
  final SettingsClient? client;
  final SettingsPageSpec page;
  final ValueChanged<SettingsPageSpec> onPage;

  final SystemInformationReader? systemInformation;

  static const _pageRows = {
    'display.e32be03e': 'night-light',
    'display.2f32a8c2': 'graphics',
  };

  @override
  Widget build(BuildContext context) {
    if (page.id == 'about') {
      return SystemInformationPage(page: page, read: systemInformation);
    }
    if (page.id == 'night-light') {
      if (NightLightScope.maybeOf(context) case final controller?) {
        return NightLightPage(
          page: page,
          controller: controller,
          hdrActive: DisplayScope.maybeOf(context)?.hdrActive ?? false,
        );
      }
    }
    if (page.id == 'background') {
      if (BackgroundScope.maybeOf(context) case final controller?) {
        return BackgroundPage(
          catalog: catalog,
          page: page,
          controller: controller,
          client: client,
        );
      }
    }
    return _preview(context);
  }

  Widget _preview(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      if (page.id == 'date-time') const CurrentDateTime(),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: .center,
        children: [
          AvailabilityBadge(page.availability, reason: page.reason),
          Text(page.description, style: Theme.of(context).textTheme.bodyLarge),
        ],
      ),
      const SizedBox(height: 12),
      Text(page.reason, style: Theme.of(context).textTheme.bodySmall),
      ...leading,
      if (page.preview != 'none') ...[
        const SizedBox(height: 24),
        if (page.id == 'display' && DisplayScope.maybeOf(context) != null)
          DisplayArrangement(controller: DisplayScope.maybeOf(context)!)
        else
          SettingsPreview(page.preview),
      ],
      for (final section in page.sections)
        SettingsSectionCard(
          section,
          onPageRow: (id) => onPage(catalog.page(_pageRows[id]!)),
          pageRows: _pageRows.keys.toSet(),
          isVisible: isVisible,
          controlBuilder: controlBuilder == null
              ? null
              : (setting) =>
                    controlBuilder!(setting) ??
                    SettingControlTile(
                      setting,
                      onOpenPage: _pageRows.containsKey(setting.id)
                          ? () => onPage(catalog.page(_pageRows[setting.id]!))
                          : null,
                    ),
        ),
      if (page.children.isNotEmpty) ...[
        const SettingsSectionTitle('Related settings'),
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              for (final id in page.children)
                PageLink(
                  page: catalog.page(id),
                  icon: categoryIcon(catalog.category(page.category).icon),
                  onTap: () => onPage(catalog.page(id)),
                ),
            ],
          ),
        ),
      ],
    ],
  );
}

class SettingsSectionCard extends StatelessWidget {
  const SettingsSectionCard(
    this.section, {
    super.key,
    required this.onPageRow,
    required this.pageRows,
    this.controlBuilder,
    this.isVisible,
  });
  final SettingsSection section;
  final ValueChanged<String> onPageRow;
  final Set<String> pageRows;
  final Widget Function(SettingSpec)? controlBuilder;
  final bool Function(SettingSpec)? isVisible;

  @override
  Widget build(BuildContext context) {
    final visible = section.controls
        .where((setting) => isVisible?.call(setting) ?? true)
        .where(
          (setting) => switch (setting.id) {
            displayDetectId => false,
            manualTimeSettingId =>
              DateTimeScope.maybeOf(context)?.hideManualTime != true,
            timeServerSettingId || syncNowSettingId =>
              DateTimeScope.maybeOf(context)?.state?.ntp == true,
            _ => true,
          },
        )
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final controls = Column(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i != 0) const Divider(height: 1, indent: 20, endIndent: 20),
          controlBuilder?.call(visible[i]) ??
              SettingControlTile(
                visible[i],
                onOpenPage: pageRows.contains(visible[i].id)
                    ? () => onPageRow(visible[i].id)
                    : null,
              ),
        ],
      ],
    );
    if (section.collapsed) {
      final bodyKey = PageStorageKey('body-${section.controls.first.id}');
      final tileKey = PageStorageKey('reference-${section.controls.first.id}');
      // Keep expansion and nested scroll positions in separate storage slots.
      final body = KeyedSubtree(key: bodyKey, child: controls);
      if (section.title == 'Advanced') {
        return AdvancedSection(storageKey: tileKey, child: body);
      }
      return AdvancedSection(
        storageKey: tileKey,
        title: section.title,
        subtitle:
            section.description ??
            'Reference options that are not implemented yet',
        icon: Icons.library_books_outlined,
        child: body,
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SettingsSectionTitle(section.title),
        SettingsSurface(padding: .zero, child: controls),
      ],
    );
  }
}
