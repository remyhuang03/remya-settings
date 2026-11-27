import 'package:material_ui/material_ui.dart';

import 'package:remya_ui/settings_ui.dart';

import '../domain/settings_catalog.dart';
import 'color_button.dart';
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
  'remya_apps' => Icons.widgets_outlined,
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
      'keyboard' => Icons.keyboard_outlined,
      'time-more' || 'system-more' || 'appearance-more' => Icons.add_rounded,
      'keyboard-shortcuts' => Icons.keyboard_command_key_rounded,
      'speech' => Icons.record_voice_over_outlined,
      final id when id.startsWith('regionlanguage-') =>
        Icons.keyboard_alt_outlined,
      'projection' => Icons.desktop_windows_outlined,
      'night-light' => Icons.nightlight_outlined,
      'graphics' => Icons.memory_rounded,
      'volume-mixer' => Icons.tune_rounded,
      'sound-volume' => Icons.volume_up_outlined,
      'sound-devices' => Icons.speaker_outlined,
      'ai-providers' => Icons.hub_outlined,
      'focus' => Icons.do_not_disturb_on_outlined,
      'themes' => Icons.palette_outlined,
      'background' => Icons.wallpaper_outlined,
      'fonts' => Icons.text_fields_rounded,
      'accessibility-vision' => Icons.visibility_outlined,
      'narrator' => Icons.record_voice_over_outlined,
      'accessibility-hearing' => Icons.hearing_outlined,
      'accessibility-interaction' => Icons.touch_app_outlined,
      'bluetooth' => Icons.bluetooth_rounded,
      'printers' => Icons.print_outlined,
      'cameras' => Icons.camera_alt_outlined,
      'mouse' => Icons.mouse_outlined,
      'cursor' => Icons.ads_click_outlined,
      'multitasking' => Icons.space_dashboard_outlined,
      'workspaces' => Icons.workspaces_outlined,
      'environment-variables' => Icons.data_object_rounded,
      'window-appearance' => Icons.rounded_corner_outlined,
      'animations' => Icons.animation_outlined,
      'touchpad' => Icons.touch_app_outlined,
      'touch' => Icons.tablet_mac_outlined,
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
      'window-rules' => Icons.rule_rounded,
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
      control: setting.kind == .info
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
    // System previews stay disabled until real integrations are verified.
    return switch (setting.kind) {
      .toggle => Switch(value: setting.value as bool, onChanged: null),
      .slider => SizedBox(
        width: 220,
        child: SettingsSlider(
          value: (setting.value as num).toDouble(),
          min: setting.min,
          max: setting.max,
          onChanged: null,
        ),
      ),
      .choice => SettingsChoice<String>(
        label: setting.title,
        choices: {for (final option in setting.options) option: option},
        selected: setting.value as String,
        width: 232,
        onSelected: null,
      ),
      .action => SettingsButton(
        label: setting.value as String,
        onPressed: null,
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
      .color => ColorButton(
        color: setting.value as String,
        title: setting.title,
        onChanged: null,
      ),
    };
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

/// A whole-row link to another page with its availability beside the chevron.
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
  Widget build(BuildContext context) => SettingsLinkRow(
    icon: icon,
    title: title,
    subtitle: subtitle,
    trailing: availability == .available
        ? null
        : AvailabilityBadge(availability, reason: reason),
    onTap: onTap,
  );
}
