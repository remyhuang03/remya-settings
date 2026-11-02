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
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Container(
          padding: const .all(28),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: .circular(32),
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/icons/settings.png',
                width: 72,
                height: 72,
                semanticLabel: 'Settings',
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      'Your desktop, your way.',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Unavailable settings are previews',
                      style: TextStyle(
                        color: colors.onPrimaryContainer,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text('All settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 640
                ? (constraints.maxWidth - 16) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final category in catalog.categories)
                  SizedBox(
                    width: width,
                    child: _CategoryCard(
                      category: category,
                      pages: catalog.inCategory(category.id).length,
                      onTap: () => onCategory(category.id),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 24),
        Text(
          '${catalog.categories.length} categories · ${catalog.pages.length} pages · ${catalog.controlCount} settings\nSample data is for layout previews and does not represent your device.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.pages,
    required this.onTap,
  });
  final SettingsCategory category;
  final int pages;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLowest,
      borderRadius: .circular(24),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .all(22),
          child: Row(
            children: [
              Container(
                padding: const .all(13),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: .circular(18),
                ),
                child: Icon(
                  categoryIcon(category.icon),
                  color: colors.onSecondaryContainer,
                ),
              ),
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
                    const SizedBox(height: 8),
                    Text(
                      '$pages pages · Not implemented',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colors.onSurfaceVariant),
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
  });
  final SettingsCatalog catalog;
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
        return BackgroundPage(page: page, controller: controller);
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
      if (page.preview != 'none') ...[
        const SizedBox(height: 24),
        if (page.id == 'display' && DisplayScope.maybeOf(context) != null)
          DisplayArrangement(controller: DisplayScope.maybeOf(context)!)
        else
          SettingsPreview(page.preview),
      ],
      for (final section in page.sections)
        _SectionCard(
          section,
          onPageRow: (id) => onPage(catalog.page(_pageRows[id]!)),
          pageRows: _pageRows.keys.toSet(),
        ),
      if (page.children.isNotEmpty) ...[
        Padding(
          padding: const .only(top: 28, bottom: 12),
          child: Text(
            'Related settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
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
      const SizedBox(height: 24),
      Text(
        'Unimplemented settings use sample values, not detected device state.',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
    this.section, {
    required this.onPageRow,
    required this.pageRows,
  });
  final SettingsSection section;
  final ValueChanged<String> onPageRow;
  final Set<String> pageRows;

  @override
  Widget build(BuildContext context) {
    final visible = section.controls
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
      return Padding(
        padding: const .only(top: 24),
        child: SettingsSurface(
          padding: .zero,
          child: ExpansionTile(
            key: tileKey,
            title: Text(section.title),
            subtitle: Text(
              section.description ??
                  'Additional reference options · Not implemented',
            ),
            children: [body],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Padding(
          padding: const .only(top: 28, bottom: 12),
          child: Text(
            section.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SettingsSurface(padding: .zero, child: controls),
      ],
    );
  }
}
