import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

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
    switch (page.id) {
      'date-time' => Icons.schedule_rounded,
      'about' => Icons.info_outline_rounded,
      'language' => Icons.translate_rounded,
      'typing' || 'text-input' => Icons.edit_note_rounded,
      'keyboard' || 'accessibility-keyboard' => Icons.keyboard_outlined,
      'time-more' || 'system-more' || 'appearance-more' => Icons.add_rounded,
      'hypr-keybinds' => Icons.keyboard_outlined,
      'speech' ||
      'online-speech' ||
      'voice-access' => Icons.record_voice_over_outlined,
      final id when id.startsWith('regionlanguage-') =>
        Icons.keyboard_alt_outlined,
      'projection' => Icons.desktop_windows_outlined,
      'night-light' => Icons.nightlight_outlined,
      'graphics' || 'hypr-multi-gpu' => Icons.memory_rounded,
      'volume-mixer' => Icons.tune_rounded,
      'sound-volume' => Icons.volume_up_outlined,
      'sound-devices' => Icons.speaker_outlined,
      'notifications' => Icons.notifications_none_rounded,
      'focus' || 'quiet-schedule' => Icons.do_not_disturb_on_outlined,
      'themes' => Icons.palette_outlined,
      'background' => Icons.wallpaper_outlined,
      'fonts' || 'text-size' => Icons.text_fields_rounded,
      'bluetooth' => Icons.bluetooth_rounded,
      'printers' => Icons.print_outlined,
      'cameras' => Icons.camera_alt_outlined,
      'mouse' || 'pointer' || 'cursor' => Icons.mouse_outlined,
      'touchpad' => Icons.touch_app_outlined,
      'wifi' => Icons.wifi_outlined,
      'known-networks' => Icons.bookmark_outline_rounded,
      'ethernet' => Icons.lan_outlined,
      'vpn' => Icons.vpn_lock_outlined,
      'installed' => Icons.apps_rounded,
      'appimages' => Icons.inventory_2_outlined,
      'app-properties' => Icons.tune_rounded,
      'defaults' => Icons.task_alt_rounded,
      'startup' => Icons.rocket_launch_outlined,
      'lockscreen' ||
      'signin' ||
      'hypr-lock-authentication' => Icons.lock_outline_rounded,
      _ => switch (page.preview) {
        'display' => Icons.desktop_windows_outlined,
        'sound' => Icons.volume_up_outlined,
        'network' => Icons.wifi_outlined,
        'devices' => Icons.devices_other_outlined,
        'power' => Icons.battery_charging_full_rounded,
        'storage' => Icons.storage_outlined,
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

/// A page's default-collapsed advanced options, one rounded card with its rows.
class AdvancedSection extends StatelessWidget {
  const AdvancedSection({
    super.key,
    required this.storageKey,
    required this.child,
  });
  final Key storageKey;
  final Widget child;

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
            child: Icon(
              Icons.tune_rounded,
              size: 20,
              color: colors.onSecondaryContainer,
            ),
          ),
          title: Text(
            'Advanced',
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
    child: LayoutBuilder(
      builder: (context, constraints) {
        final control = this.control;
        if (control == null) {
          return Align(alignment: .centerLeft, child: label);
        }
        final compact =
            control is ButtonStyleButton ||
            control is IconButton ||
            control is Switch ||
            control is Checkbox;
        if (constraints.maxWidth < (compact ? 240 : 560)) {
          return Column(
            crossAxisAlignment: .start,
            children: [
              label,
              const SizedBox(height: 14),
              Align(alignment: .centerRight, child: control),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: label),
            const SizedBox(width: 24),
            if (compact)
              control
            else
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

class SettingControlTile extends StatelessWidget {
  const SettingControlTile(this.setting, {super.key, this.onOpenPage});
  final SettingSpec setting;

  /// Opens a related preview page from an otherwise unavailable row.
  final VoidCallback? onOpenPage;

  @override
  Widget build(BuildContext context) {
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
              if (setting.id == syncNowSettingId && state != null)
                Text(
                  clock!.isSyncing
                      ? 'Syncing…'
                      : state.syncError != null
                      ? 'Time synchronization unavailable'
                      : '${state.ntpSynchronized ? 'Synchronized' : 'Not synchronized'}${state.activeTimeServer.isEmpty ? '' : ' · ${state.activeTimeServer}'}',
                  style: detailStyle,
                ),
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
                child: onOpenPage == null
                    ? _PreviewControl(setting)
                    : FilledButton(
                        key: ValueKey('open-page-${setting.id}'),
                        onPressed: onOpenPage,
                        child: Text(setting.value as String),
                      ),
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
