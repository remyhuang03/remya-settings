import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_row_layout.dart';

import '../../appearance/application/app_preferences_controller.dart';
import '../../appearance/domain/app_preferences.dart';
import '../domain/settings_catalog.dart';
import '../../date_time/application/date_time_controller.dart';
import '../../date_time/presentation/date_time_settings.dart';
import '../../display/application/display_controller.dart';
import '../../display/presentation/display_settings.dart';

IconData categoryIcon(String icon) => switch (icon) {
  'computer' => Icons.computer_outlined,
  'devices' => Icons.devices_other_outlined,
  'volume' => Icons.volume_up_outlined,
  'wifi' => Icons.wifi_outlined,
  'palette' => Icons.palette_outlined,
  'auto_awesome' => Icons.auto_awesome_rounded,
  'apps' => Icons.apps_rounded,
  'person' => Icons.person_outline_rounded,
  'language' => Icons.language_rounded,
  'sports_esports' => Icons.sports_esports_outlined,
  'accessibility' => Icons.accessibility_new_rounded,
  'shield' => Icons.shield_outlined,
  'update' => Icons.system_update_alt_rounded,
  'power' || 'battery' => Icons.battery_charging_full_rounded,
  'notifications' || 'notification' => Icons.notifications_none_rounded,
  _ => Icons.settings_outlined,
};

IconData pageIcon(SettingsPageSpec page, SettingsCategory category) =>
    switch (page.id) {
      'storage' => Icons.storage_outlined,
      'cleanup' => Icons.cleaning_services_outlined,
      'date-time' => Icons.schedule_rounded,
      'about' => Icons.info_outline_rounded,
      'language' => Icons.translate_rounded,
      'typing' || 'text-input' => Icons.edit_note_rounded,
      'keyboard' || 'accessibility-keyboard' => Icons.keyboard_outlined,
      'time-more' || 'system-more' || 'appearance-more' => Icons.add_rounded,
      'keyboard-shortcuts' => Icons.keyboard_command_key_rounded,
      'speech' || 'online-speech' => Icons.record_voice_over_outlined,
      final id when id.startsWith('regionlanguage-') =>
        Icons.keyboard_alt_outlined,
      'projection' => Icons.desktop_windows_outlined,
      'night-light' => Icons.nightlight_outlined,
      'graphics' || 'hypr-multi-gpu' => Icons.memory_rounded,
      'volume-mixer' => Icons.tune_rounded,
      'sound-volume' => Icons.volume_up_outlined,
      'sound-devices' => Icons.speaker_outlined,
      'ai-providers' => Icons.hub_outlined,
      'ai-usage' => Icons.data_usage_rounded,
      'notifications' => Icons.notifications_none_rounded,
      'focus' || 'quiet-schedule' => Icons.do_not_disturb_on_outlined,
      'priority-notifications' => Icons.notification_important_outlined,
      'themes' => Icons.palette_outlined,
      'background' => Icons.wallpaper_outlined,
      'fonts' => Icons.text_fields_rounded,
      'text-size' => Icons.format_size_rounded,
      'bluetooth' => Icons.bluetooth_rounded,
      'printers' => Icons.print_outlined,
      'cameras' => Icons.camera_alt_outlined,
      'mouse' => Icons.mouse_outlined,
      'cursor' => Icons.ads_click_outlined,
      'multitasking' => Icons.space_dashboard_outlined,
      'workspaces' => Icons.workspaces_outlined,
      'window-appearance' => Icons.rounded_corner_outlined,
      'animations' => Icons.animation_outlined,
      'touchpad' => Icons.touch_app_outlined,
      'airplane' => Icons.airplanemode_active_rounded,
      'wifi' => Icons.wifi_outlined,
      'known-networks' => Icons.bookmark_outline_rounded,
      'ethernet' => Icons.lan_outlined,
      'vpn' => Icons.vpn_lock_outlined,
      'hotspot' => Icons.wifi_tethering_rounded,
      'proxy' => Icons.alt_route_rounded,
      'network-status' => Icons.network_check_rounded,
      'installed' => Icons.apps_rounded,
      'appimages' => Icons.inventory_2_outlined,
      'app-properties' => Icons.tune_rounded,
      'defaults' => Icons.task_alt_rounded,
      'startup' => Icons.rocket_launch_outlined,
      'lockscreen' || 'signin' => Icons.lock_outline_rounded,
      'power' => Icons.battery_charging_full_rounded,
      'battery-saver' => Icons.battery_saver_rounded,
      'battery-usage' => Icons.bar_chart_rounded,
      _ => switch (page.preview) {
        'display' => Icons.desktop_windows_outlined,
        'sound' => Icons.volume_up_outlined,
        'network' => Icons.wifi_outlined,
        'devices' => Icons.devices_other_outlined,
        'volume' => Icons.volume_up_outlined,
        'power' => Icons.battery_charging_full_rounded,
        'personalization' => Icons.palette_outlined,
        'update' => Icons.system_update_alt_rounded,
        _ => categoryIcon(category.icon),
      },
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
            Flexible(
              child: Text(
                availability.label,
                style: TextStyle(fontSize: 11, fontWeight: .w600, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

ButtonStyle destructiveFilledButtonStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: colors.error,
    foregroundColor: colors.onError,
  );
}

ButtonStyle destructiveTonalButtonStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return FilledButton.styleFrom(
    backgroundColor: colors.errorContainer,
    foregroundColor: colors.onErrorContainer,
  );
}

ButtonStyle destructiveTextButtonStyle(BuildContext context) =>
    TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error);

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

/// The heading above a group of settings.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(top: 28, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Rows of one settings group, separated by inset dividers.
Widget settingsRows(List<Widget> rows) => Column(
  children: [
    for (var i = 0; i < rows.length; i++) ...[
      if (i != 0) const Divider(height: 1, indent: 20, endIndent: 20),
      rows[i],
    ],
  ],
);

/// A page-level failure with its message and a Retry action.
class SettingsErrorCard extends StatelessWidget {
  const SettingsErrorCard({super.key, required this.message, this.onRetry});
  final String message;

  /// Null while a retry cannot start, such as during another operation.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const .only(bottom: 12),
      child: SettingsSurface(
        child: SettingsRowLayout(
          left: Row(
            mainAxisSize: .min,
            children: [
              Icon(Icons.error_outline_rounded, color: colors.error),
              const SizedBox(width: 16),
              Flexible(
                child: Semantics(liveRegion: true, child: Text(message)),
              ),
            ],
          ),
          right: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      ),
    );
  }
}

/// A page's default-collapsed options, one rounded card with its rows.
class AdvancedSection extends StatelessWidget {
  const AdvancedSection({
    super.key,
    required this.storageKey,
    required this.child,
    this.title = 'Advanced',
    this.subtitle,
    this.icon = Icons.tune_rounded,
  });
  final Key storageKey;
  final Widget child;
  final String title;
  final String? subtitle;
  final IconData icon;

  static const _radius = BorderRadius.all(.circular(28));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const shape = RoundedRectangleBorder(borderRadius: _radius);
    return Padding(
      padding: const .only(top: 24),
      child: Material(
        color: colors.surfaceContainerLowest,
        borderRadius: _radius,
        clipBehavior: .antiAlias,
        child: ExpansionTile(
          key: storageKey,
          tilePadding: const .symmetric(horizontal: 20, vertical: 6),
          shape: shape,
          collapsedShape: shape,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              shape: .circle,
            ),
            child: Icon(icon, size: 20, color: colors.onSecondaryContainer),
          ),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: subtitle == null ? null : Text(subtitle!),
          children: [
            const Divider(height: 1, indent: 20, endIndent: 20),
            child,
          ],
        ),
      ),
    );
  }
}

/// Information on the left, the interactive control on the right; stacked when narrow.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.id,
    required this.label,
    this.control,
  });
  final String id;
  final Widget label;
  final Widget? control;

  @override
  Widget build(BuildContext context) => Padding(
    key: ValueKey(id),
    padding: const .symmetric(horizontal: 20, vertical: 18),
    child: control == null
        ? Align(alignment: .centerLeft, heightFactor: 1, child: label)
        : SettingsRowLayout(left: label, right: control!),
  );
}

class SettingControlTile extends StatelessWidget {
  const SettingControlTile(
    this.setting, {
    super.key,
    this.onOpenPage,
    this.icon,
  });
  final SettingSpec setting;

  /// Turns the row into a link to a related page, including preview pages.
  final VoidCallback? onOpenPage;

  /// Leading icon of a page link, matching neighboring [PageLink] rows.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (onOpenPage case final open?) {
      return _LinkRow(
        key: ValueKey('open-page-${setting.id}'),
        icon: icon,
        title: setting.title,
        subtitle: setting.availability == .available ? setting.reason : null,
        availability: setting.availability,
        reason: setting.reason,
        onTap: open,
      );
    }
    if (displaySettingIds.contains(setting.id)) {
      final controller = DisplayScope.maybeOf(context);
      if (controller != null) {
        return DisplaySettingRow(setting: setting, controller: controller);
      }
    }
    return SettingRow(
      id: setting.id,
      label: Builder(
        builder: (context) {
          final clock = DateTimeScope.maybeOf(context);
          final state = clock?.state;
          final detailStyle = Theme.of(context).textTheme.bodySmall;
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
              if (setting.id == accentColorSettingId) const _AccentReadout(),
              if (dateTimeSettingIds.contains(setting.id) && state == null)
                Text('System settings unavailable', style: detailStyle),
              if (setting.id == syncNowSettingId && state != null) ...[
                Text(
                  clock!.isSyncing
                      ? 'Syncing…'
                      : state.syncError != null
                      ? 'Time synchronization unavailable'
                      : state.ntpSynchronized
                      ? 'Synchronized'
                      : 'Not synchronized',
                  style: detailStyle,
                ),
                if (!clock.isSyncing &&
                    state.syncError == null &&
                    state.activeTimeServer.isNotEmpty)
                  Text('Server: ${state.activeTimeServer}', style: detailStyle),
              ],
              if (setting.kind == .info)
                Text(setting.value as String, style: detailStyle),
              if (setting.kind == .slider)
                Text(
                  'Sample ${setting.value}${setting.unit}',
                  style: detailStyle,
                ),
            ],
          );
          return label;
        },
      ),
      control:
          setting.kind == .info ||
              // The sampled color is a readout; a picker only applies to Custom.
              setting.id == accentColorSettingId &&
                  AppPreferencesScope.of(context).accentSource == 'background'
          ? null
          : Semantics(
              label:
                  '${setting.title}, ${setting.availability.label}. ${setting.reason}',
              enabled: setting.availability == .available ? null : false,
              child: Tooltip(
                message: setting.reason,
                child: _PreviewControl(setting),
              ),
            ),
    );
  }
}

class _PreviewControl extends StatelessWidget {
  const _PreviewControl(this.setting);
  final SettingSpec setting;

  @override
  Widget build(BuildContext context) {
    if (dateTimeSettingIds.contains(setting.id)) {
      return DateTimeSettingControl(setting.id);
    }
    if (setting.id == materialStyleSettingId) {
      return _AppStyleChoice(setting);
    }
    if (setting.id == materialThemeModeSettingId) {
      return const _AppThemeModeChoice();
    }
    if (setting.id == accentSourceSettingId) {
      return _AccentSourceChoice(setting);
    }
    if (setting.id == accentColorSettingId) {
      return const _AccentColorButton();
    }
    // System previews stay disabled until real integrations are verified.
    return switch (setting.kind) {
      .toggle => Switch(value: setting.value as bool, onChanged: null),
      .slider => SizedBox(
        width: 220,
        child: Slider(
          value: (setting.value as num).toDouble(),
          min: setting.min,
          max: setting.max,
          onChanged: null,
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
      .action => FilledButton(
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
      .info => const SizedBox.shrink(),
      .color => FilledButton.icon(
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

class _AppStyleChoice extends StatelessWidget {
  const _AppStyleChoice(this.setting);
  final SettingSpec setting;

  @override
  Widget build(BuildContext context) {
    final controller = AppPreferencesScope.of(context);
    final value = controller.preferences.styleVariant.label;
    return SizedBox(
      width: 232,
      child: DropdownButtonFormField<String>(
        key: ValueKey('control-${setting.id}'),
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
        onChanged: (value) {
          if (value == null || controller.isBusy) return;
          controller.setStyleVariant(
            DynamicSchemeVariant.values.firstWhere(
              (item) => item.label == value,
            ),
          );
        },
      ),
    );
  }
}

class _AppThemeModeChoice extends StatelessWidget {
  const _AppThemeModeChoice();

  @override
  Widget build(BuildContext context) {
    final controller = AppPreferencesScope.of(context);
    return Row(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        for (final mode in SystemThemeMode.values)
          IconButton.filledTonal(
            key: ValueKey('$materialThemeModeSettingId-${mode.label}'),
            tooltip: mode.label,
            isSelected: controller.preferences.themeMode == mode,
            onPressed: controller.systemTheme == null
                ? null
                : () {
                    if (!controller.isBusy) controller.setThemeMode(mode);
                  },
            icon: Icon(switch (mode) {
              .light => Icons.light_mode_outlined,
              .dark => Icons.dark_mode_outlined,
            }),
            selectedIcon: Icon(switch (mode) {
              .light => Icons.light_mode_rounded,
              .dark => Icons.dark_mode_rounded,
            }),
          ),
      ],
    );
  }
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _AccentReadout extends StatelessWidget {
  const _AccentReadout();

  @override
  Widget build(BuildContext context) {
    final controller = AppPreferencesScope.of(context);
    final style = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: .start,
      children: [
        const SizedBox(height: 4),
        Text(
          _hex(controller.preferences.seedColor),
          key: const ValueKey('accent-readout'),
          style: style.bodyMedium,
        ),
        if (controller.accentError case final error?)
          Text(
            'Could not sample the background. The last color is kept. $error',
            style: style.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
      ],
    );
  }
}

class _AccentSourceChoice extends StatelessWidget {
  const _AccentSourceChoice(this.setting);
  final SettingSpec setting;

  @override
  Widget build(BuildContext context) {
    final controller = AppPreferencesScope.of(context);
    return SizedBox(
      width: 232,
      child: DropdownButtonFormField<String>(
        key: ValueKey('control-${setting.id}-${controller.accentSource}'),
        initialValue: controller.accentSource,
        isExpanded: true,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(borderRadius: .all(.circular(14))),
        ),
        items: const [
          DropdownMenuItem(value: 'background', child: Text('From background')),
          DropdownMenuItem(value: 'custom', child: Text('Custom')),
        ],
        onChanged: (value) {
          if (value != null && !controller.isBusy) {
            controller.setAccentSource(value);
          }
        },
      ),
    );
  }
}

class _AccentColorButton extends StatelessWidget {
  const _AccentColorButton();

  Future<void> _pick(
    BuildContext context,
    AppPreferencesController controller,
  ) async {
    var picked = controller.preferences.seedColor;
    final confirmed = await ColorPicker(
      color: picked,
      onColorChanged: (color) => picked = color,
      pickersEnabled: const {
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
        ColorPickerType.wheel: true,
      },
      enableShadesSelection: true,
      showColorCode: true,
      colorCodeHasColor: true,
      heading: Text(
        'Accent color',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      subheading: const Text('Shades'),
      wheelSubheading: const Text('Shades'),
    ).showPickerDialog(context);
    if (confirmed) await controller.setAccentColor(_hex(picked));
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppPreferencesScope.of(context);
    return FilledButton.icon(
      key: const ValueKey('accent-color-button'),
      onPressed: controller.isBusy ? null : () => _pick(context, controller),
      icon: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: controller.preferences.seedColor,
          shape: .circle,
        ),
      ),
      label: const Text('Choose color'),
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
  Widget build(BuildContext context) => _LinkRow(
    key: ValueKey('page-link-${page.id}'),
    icon: icon,
    title: page.title,
    subtitle: subtitle ?? page.description,
    availability: page.availability,
    reason: page.reason,
    onTap: onTap,
  );
}

/// A whole-row link to another page: text on the left, status and chevron on the right.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.availability,
    required this.reason,
    required this.onTap,
  });
  final IconData? icon;
  final String title;
  final String? subtitle;
  final SettingAvailability availability;
  final String reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const .symmetric(horizontal: 20, vertical: 16),
          child: SettingsRowLayout(
            left: Row(
              mainAxisSize: .min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 16),
                ],
                Flexible(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Text(title, style: text.bodyLarge),
                      if (subtitle case final subtitle?) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, style: text.bodySmall),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            right: Row(
              mainAxisSize: .min,
              spacing: 12,
              children: [
                if (availability != .available)
                  AvailabilityBadge(availability, reason: reason),
                const Icon(Icons.chevron_right_rounded, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
