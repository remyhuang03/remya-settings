import 'package:material_ui/material_ui.dart';

import '../domain/settings_catalog.dart';
import 'settings_preview.dart';
import 'settings_widgets.dart';

class SettingsHome extends StatelessWidget {
  const SettingsHome({
    super.key,
    required this.catalog,
    required this.onCategory,
    required this.onPage,
  });
  final SettingsCatalog catalog;
  final ValueChanged<String> onCategory;
  final ValueChanged<SettingsPageSpec> onPage;

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
                semanticLabel: '设置',
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: [
                    Text(
                      '你的桌面，由你定义。',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '为 Hyprland 打造的全局系统设置',
                      style: TextStyle(color: colors.onPrimaryContainer),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'UI 预览 · 系统功能尚未实现',
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
        Text('常用设置', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              for (final (id, icon) in [
                ('display', Icons.desktop_windows_outlined),
                ('sound', Icons.volume_up_outlined),
                ('wifi', Icons.wifi_outlined),
                ('background', Icons.wallpaper_outlined),
              ])
                PageLink(
                  page: catalog.page(id),
                  icon: icon,
                  onTap: () => onPage(catalog.page(id)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Text('所有设置', style: Theme.of(context).textTheme.titleLarge),
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
          '${catalog.categories.length} 个分类 · ${catalog.pages.length} 个页面 · ${catalog.controlCount} 个设置项\n示例数据仅用于布局预览，不代表当前设备配置。',
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
                      '$pages 个页面 · 系统功能未实现',
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

class SettingsCategoryView extends StatelessWidget {
  const SettingsCategoryView({
    super.key,
    required this.catalog,
    required this.category,
    required this.onPage,
  });
  final SettingsCatalog catalog;
  final SettingsCategory category;
  final ValueChanged<SettingsPageSpec> onPage;

  @override
  Widget build(BuildContext context) {
    final pages = catalog.inCategory(category.id);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          category.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 20),
        for (final (status, title) in [
          (SettingAvailability.available, '已实现的设置'),
          (SettingAvailability.planned, '设置'),
          (SettingAvailability.unsupported, '平台专属和旧版参考'),
        ])
          if (pages.any((p) => p.availability == status)) ...[
            Padding(
              padding: const .only(bottom: 12, top: 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            SettingsSurface(
              padding: .zero,
              child: Column(
                children: [
                  for (final page in pages.where(
                    (p) => p.availability == status,
                  ))
                    PageLink(
                      page: page,
                      icon: categoryIcon(category.icon),
                      onTap: () => onPage(page),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

class SettingsDetail extends StatelessWidget {
  const SettingsDetail({
    super.key,
    required this.catalog,
    required this.page,
    required this.onPage,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final ValueChanged<SettingsPageSpec> onPage;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
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
        SettingsPreview(page.preview),
      ],
      for (final section in page.sections) _SectionCard(section),
      if (page.children.isNotEmpty) ...[
        Padding(
          padding: const .only(top: 28, bottom: 12),
          child: Text('相关设置', style: Theme.of(context).textTheme.titleMedium),
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
      Text('所有数值、设备和账户均为预览示例。', style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(this.section);
  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final controls = Column(
      children: [
        for (var i = 0; i < section.controls.length; i++) ...[
          if (i != 0) const Divider(height: 1, indent: 20, endIndent: 20),
          SettingControlTile(section.controls[i]),
        ],
      ],
    );
    if (section.collapsed) {
      return Padding(
        padding: const .only(top: 24),
        child: SettingsSurface(
          padding: .zero,
          child: ExpansionTile(
            key: PageStorageKey('reference-${section.controls.first.id}'),
            title: Text(section.title),
            subtitle: const Text('保留原始名称的补充预览选项 · 均未实现'),
            children: [controls],
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
