import 'package:material_ui/material_ui.dart';

import '../../appearance/application/app_preferences_controller.dart';
import '../../appearance/domain/app_preferences.dart';
import '../domain/settings_catalog.dart';

IconData categoryIcon(String icon) => switch (icon) {
  'computer' => Icons.computer_outlined,
  'devices' => Icons.devices_other_outlined,
  'wifi' => Icons.wifi_outlined,
  'palette' => Icons.palette_outlined,
  'apps' => Icons.apps_rounded,
  'person' => Icons.person_outline_rounded,
  'language' => Icons.language_rounded,
  'sports_esports' => Icons.sports_esports_outlined,
  'accessibility' => Icons.accessibility_new_rounded,
  'shield' => Icons.shield_outlined,
  'update' => Icons.system_update_alt_rounded,
  _ => Icons.settings_outlined,
};

IconData pageIcon(SettingsPageSpec page, SettingsCategory category) =>
    switch (page.preview) {
      'display' => Icons.desktop_windows_outlined,
      'sound' => Icons.volume_up_outlined,
      'network' => Icons.wifi_outlined,
      'devices' => Icons.devices_other_outlined,
      'power' => Icons.battery_charging_full_rounded,
      'storage' => Icons.storage_outlined,
      'personalization' => Icons.palette_outlined,
      'update' => Icons.system_update_alt_rounded,
      _ => categoryIcon(category.icon),
    };

class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge(this.availability, {super.key, this.reason});
  final SettingAvailability availability;
  final String? reason;

  @override
  Widget build(BuildContext context) {
    if (availability == .available) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final (icon, color, background) = switch (availability) {
      .available => (
        Icons.check_circle_outline,
        colors.primary,
        colors.primaryContainer,
      ),
      .planned => (
        Icons.construction_rounded,
        colors.onSecondaryContainer,
        colors.secondaryContainer,
      ),
      .unsupported => (
        Icons.block_rounded,
        colors.onSurfaceVariant,
        colors.surfaceContainerHighest,
      ),
    };
    return Tooltip(
      message: reason ?? availability.description,
      child: Container(
        padding: const .symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          borderRadius: .circular(20),
        ),
        child: Row(
          mainAxisSize: .min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              availability.label,
              style: TextStyle(fontSize: 11, fontWeight: .w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsSurface extends StatelessWidget {
  const SettingsSurface({
    super.key,
    required this.child,
    this.padding = const .all(20),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    borderRadius: .circular(24),
    clipBehavior: .antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class SettingControlTile extends StatelessWidget {
  const SettingControlTile(this.setting, {super.key});
  final SettingSpec setting;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey(setting.id),
      padding: const .symmetric(horizontal: 20, vertical: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final label = Column(
            crossAxisAlignment: .start,
            children: [
              Text(setting.title, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 6),
              if (setting.availability == .available)
                Text(
                  setting.reason,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                AvailabilityBadge(setting.availability, reason: setting.reason),
            ],
          );
          final control = Semantics(
            label:
                '${setting.title}, ${setting.availability.label}. ${setting.reason}',
            enabled: setting.availability == .available ? null : false,
            child: Tooltip(
              message: setting.reason,
              child: _PreviewControl(setting),
            ),
          );
          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: .start,
              children: [label, const SizedBox(height: 14), control],
            );
          }
          return Row(
            children: [
              Expanded(child: label),
              const SizedBox(width: 24),
              SizedBox(
                width: 232,
                child: Align(alignment: .centerRight, child: control),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewControl extends StatelessWidget {
  const _PreviewControl(this.setting);
  final SettingSpec setting;

  @override
  Widget build(BuildContext context) {
    if (const {
      materialStyleSettingId,
      materialThemeModeSettingId,
    }.contains(setting.id)) {
      return _AppMaterialChoice(setting);
    }
    // System previews stay disabled until real integrations are verified.
    return switch (setting.kind) {
      .toggle => Switch(value: setting.value as bool, onChanged: null),
      .slider => SizedBox(
        width: 220,
        child: Column(
          mainAxisSize: .min,
          children: [
            Slider(
              value: (setting.value as num).toDouble(),
              min: setting.min,
              max: setting.max,
              onChanged: null,
            ),
            Text(
              'Sample ${setting.value}${setting.unit}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      .choice => SizedBox(
        width: 232,
        child: DropdownButtonFormField<String>(
          initialValue: setting.value as String,
          isExpanded: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: .all(.circular(14))),
          ),
          items: [
            for (final option in setting.options)
              DropdownMenuItem(
                value: option,
                child: Text(option, overflow: .ellipsis),
              ),
          ],
          onChanged: null,
        ),
      ),
      .action => OutlinedButton(
        onPressed: null,
        child: Text(setting.value as String),
      ),
      .text => SizedBox(
        width: 232,
        child: TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: setting.title,
            isDense: true,
            border: const OutlineInputBorder(borderRadius: .all(.circular(14))),
          ),
        ),
      ),
      .info => Text(
        setting.value as String,
        textAlign: .end,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      .color => OutlinedButton.icon(
        onPressed: null,
        icon: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Color(
              int.parse(
                (setting.value as String).replaceFirst('#', 'FF'),
                radix: 16,
              ),
            ),
            shape: .circle,
          ),
        ),
        label: Text('Sample ${setting.value}'),
      ),
    };
  }
}

class _AppMaterialChoice extends StatelessWidget {
  const _AppMaterialChoice(this.setting);
  final SettingSpec setting;

  @override
  Widget build(BuildContext context) {
    final controller = AppPreferencesScope.of(context);
    final style = setting.id == materialStyleSettingId;
    final value = style
        ? controller.preferences.styleVariant.label
        : controller.preferences.themeMode.label;
    return SizedBox(
      width: 232,
      child: DropdownButtonFormField<String>(
        key: ValueKey('${setting.id}-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(borderRadius: .all(.circular(14))),
        ),
        items: [
          for (final option in setting.options)
            DropdownMenuItem(value: option, child: Text(option)),
        ],
        onChanged: controller.isBusy || !style && controller.systemTheme == null
            ? null
            : (value) {
                if (value == null) return;
                if (style) {
                  controller.setStyleVariant(
                    DynamicSchemeVariant.values.firstWhere(
                      (item) => item.label == value,
                    ),
                  );
                } else {
                  controller.setThemeMode(
                    SystemThemeMode.values.firstWhere(
                      (item) => item.label == value,
                    ),
                  );
                }
              },
      ),
    );
  }
}

class PageLink extends StatelessWidget {
  const PageLink({
    super.key,
    required this.page,
    required this.icon,
    required this.onTap,
    this.subtitle,
  });
  final SettingsPageSpec page;
  final IconData icon;
  final VoidCallback onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < 560;
      return ListTile(
        key: ValueKey('page-link-${page.id}'),
        contentPadding: const .symmetric(horizontal: 20, vertical: 8),
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(page.title),
        subtitle: Padding(
          padding: const .only(top: 5),
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(subtitle ?? page.description),
              if (compact) ...[
                const SizedBox(height: 8),
                AvailabilityBadge(page.availability, reason: page.reason),
              ],
            ],
          ),
        ),
        trailing: Row(
          mainAxisSize: .min,
          children: [
            if (!compact) ...[
              AvailabilityBadge(page.availability, reason: page.reason),
              const SizedBox(width: 12),
            ],
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
        onTap: onTap,
      );
    },
  );
}
