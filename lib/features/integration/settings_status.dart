import '../sound/application/sound_controller.dart';
import '../settings/presentation/settings_row_layout.dart';
import '../default_apps/application/default_apps_controller.dart';
import '../network/application/network_controller.dart';
import '../system_information/application/hostname_controller.dart';

import 'package:material_ui/material_ui.dart';

import '../appearance/application/app_preferences_controller.dart';
import '../background/application/background_controller.dart';
import '../date_time/application/date_time_controller.dart';
import '../display/application/display_controller.dart';
import '../display/presentation/display_settings.dart';
import '../night_light/application/night_light_controller.dart';

class SettingsStatus extends StatelessWidget {
  const SettingsStatus({
    super.key,
    required this.preferences,
    this.dateTime,
    this.display,
    this.nightLight,
    this.background,
    this.defaultApps,
    this.network,
    this.sound,
    this.navigatorKey,
  });
  final AppPreferencesController preferences;
  final BackgroundController? background;
  final DefaultAppsController? defaultApps;
  final NetworkController? network;
  final SoundController? sound;
  final DateTimeController? dateTime;
  final DisplayController? display;
  final NightLightController? nightLight;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      preferences,
      dateTime,
      display,
      nightLight,
      background,
      defaultApps,
      network,
      sound,
    ]),
    builder: (context, _) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.5,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          children: [
            if (preferences.errorMessage case final message?)
              _ConflictWarning(
                navigatorKey: navigatorKey,
                area: 'Appearance',
                title: '$message\n${preferences.store.file.path}',
                busy: preferences.isBusy,
                useSystem: preferences.retry,
              ),
            if (preferences.hasConflict)
              _ConflictWarning(
                navigatorKey: navigatorKey,
                area: 'Appearance',
                title:
                    'System: ${preferences.systemTheme!.mode!.name}\nSettings: ${preferences.preferences.themeMode.name}',
                busy: preferences.isBusy,
                useSystem: preferences.useSystemConfiguration,
                useSettings: () =>
                    preferences.setThemeMode(preferences.preferences.themeMode),
              ),
            if (dateTime case final controller?) ...[
              if (controller.hasConflict)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  title: controller.conflictSummary,
                  area: 'Date and time',
                  busy: controller.isBusy,
                  useSystem: controller.useSystemConfiguration,
                  useSettings: controller.applySavedConfiguration,
                ),
              if (controller.restartSuggested && !controller.restartDeferred)
                _RestartNotice(controller, navigatorKey),
              if (controller.errorMessage != null)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Date and time',
                  title: controller.errorMessage!,
                  busy: controller.isBusy,
                  useSystem: controller.retry,
                ),
            ],
            if (sound case final controller?) ...[
              if (controller.errorMessage case final message?)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Sound',
                  title: message,
                  busy: controller.isBusy,
                  useSystem: controller.refresh,
                ),
            ],
            if (defaultApps case final controller?) ...[
              if (controller.hasConflict)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Default apps',
                  title:
                      'Open Apps > Default apps to inspect each association.',
                  busy: controller.isBusy,
                  useSystem: controller.useSystemConfiguration,
                  useSettings: controller.applySavedConfiguration,
                ),
              if (controller.errorMessage case final message?)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Default apps',
                  title: message,
                  busy: controller.isBusy,
                  useSystem: controller.reload,
                ),
            ],
            if (nightLight case final controller?) ...[
              if (controller.hasConflict)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  title: controller.conflictSummary,
                  area: 'Night light',
                  busy: controller.isBusy,
                  useSystem: controller.useSystemConfiguration,
                  useSettings: controller.applySavedConfiguration,
                ),
              if (controller.errorMessage case final message?)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Night light',
                  title: message,
                  busy: controller.isBusy,
                  useSystem: controller.reload,
                ),
            ],
            if (network case final controller?) ...[
              if (controller.hasConflict)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  title: controller.conflictSummary,
                  area: 'Network',
                  busy: controller.isBusy,
                  useSystem: controller.useSystemConfiguration,
                  useSettings: controller.applySavedConfiguration,
                ),
              if (controller.errorMessage case final message?)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Network',
                  title: message,
                  busy: controller.isBusy,
                  useSystem: controller.configInvalid
                      ? controller.useSystemConfiguration
                      : controller.reload,
                  retryLabel: controller.configInvalid
                      ? 'Use system configuration'
                      : 'Retry',
                ),
            ],
            if (background case final controller?) ...[
              if (controller.hasConflict)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  title: controller.conflictSummary,
                  area: 'Background',
                  busy: controller.isBusy,
                  useSystem: controller.useSystemConfiguration,
                  useSettings: controller.applySavedConfiguration,
                ),
              if (controller.writeBlocked case final reason?)
                _StatusCard(
                  error: true,
                  icon: Icons.lock_outline_rounded,
                  title: 'hyprpaper configuration is read-only',
                  message: reason,
                  actions: [
                    TextButton.icon(
                      onPressed: controller.isBusy ? null : controller.reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              if (controller.errorMessage case final message?)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Background',
                  title: message,
                  busy: controller.isBusy,
                  useSystem: controller.retry,
                ),
            ],
            if (display case final controller?) ...[
              DisplayConfirmation(
                key: const ValueKey('display-confirmation'),
                controller: controller,
                navigatorKey: navigatorKey,
              ),
              if (controller.hasConflict)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  title: controller.conflictSummary,
                  area: 'Display',
                  busy: controller.isBusy,
                  useSystem: controller.useSystemConfiguration,
                  useSettings: controller.applySavedConfiguration,
                ),
              if (controller.writeBlocked case final reason?)
                _StatusCard(
                  error: true,
                  icon: Icons.lock_outline_rounded,
                  title: 'Display configuration is read-only',
                  message: reason,
                  actions: [
                    TextButton.icon(
                      onPressed: controller.isBusy ? null : controller.reload,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              if (controller.errorMessage case final message?)
                _ConflictWarning(
                  navigatorKey: navigatorKey,
                  area: 'Display',
                  title: message,
                  busy: controller.isBusy,
                  useSystem: controller.retry,
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

class HostnameStatus extends StatelessWidget {
  const HostnameStatus({
    super.key,
    required this.controller,
    this.navigatorKey,
  });
  final HostnameController controller;
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.4,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: .min,
          children: [
            if (controller.hasConflict)
              _ConflictWarning(
                navigatorKey: navigatorKey,
                title:
                    'System: ${controller.staticHostname}\nSettings: ${controller.savedHostname}',
                area: 'Device name',
                busy: controller.isBusy,
                useSystem: controller.useSystemConfiguration,
                useSettings: controller.applySavedConfiguration,
              ),
            if (controller.errorMessage case final message?)
              _ConflictWarning(
                navigatorKey: navigatorKey,
                area: 'Device name',
                title: message,
                busy: controller.isBusy,
                useSystem: controller.retry,
              ),
          ],
        ),
      ),
    ),
  );
}

class _ConflictWarning extends StatelessWidget {
  const _ConflictWarning({
    required this.area,
    required this.title,
    required this.busy,
    required this.useSystem,
    this.useSettings,
    this.navigatorKey,
    this.retryLabel = 'Retry',
  });

  /// The error action; replacing an unreadable file says so.
  final String retryLabel;

  /// The feature the warning belongs to, such as "Sound".
  final String area;

  /// The error message or the conflict summary.
  final String title;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool busy;
  final Future<void> Function() useSystem;
  final Future<void> Function()? useSettings;

  Future<void> _resolve(Future<void> Function() action) async {
    // Controllers retain failures so the warning survives an unsuccessful choice.
    try {
      await action();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isError = useSettings == null;
    return _StatusCard(
      error: isError,
      icon: isError ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
      title: isError
          ? '$area needs attention'
          : '$area differs from saved Settings',
      message: title,
      maxLines: isError ? 2 : null,
      actions: [
        if (isError)
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: () => showDialog<void>(
              context: navigatorKey?.currentState?.overlay?.context ?? context,
              builder: (context) => AlertDialog(
                title: Text('$area error details'),
                content: SingleChildScrollView(child: SelectableText(title)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            child: const Text('Details'),
          ),
        if (useSettings != null)
          TextButton(
            onPressed: busy ? null : () => _resolve(useSystem),
            child: const Text('Use system configuration'),
          ),
        if (isError)
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
            onPressed: busy ? null : () => _resolve(useSystem),
            icon: const Icon(Icons.refresh_rounded),
            label: Text(retryLabel),
          )
        else
          FilledButton.tonal(
            onPressed: busy ? null : () => _resolve(useSettings!),
            child: const Text('Apply Settings configuration'),
          ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actions,
    this.error = false,
    this.maxLines,
  });
  final IconData icon;
  final String title;
  final String message;
  final List<Widget> actions;
  final bool error;

  /// Long error text is truncated here; its full text stays in Details.
  final int? maxLines;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = error
        ? colors.onErrorContainer
        : colors.onPrimaryContainer;
    final label = Column(
      mainAxisSize: .min,
      crossAxisAlignment: .start,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(color: foreground),
          ),
        ),
        if (message.isNotEmpty)
          Text(
            message,
            maxLines: maxLines,
            overflow: maxLines == null ? null : .ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: foreground),
          ),
      ],
    );
    final buttons = Wrap(
      alignment: .end,
      spacing: 8,
      runSpacing: 4,
      children: actions,
    );
    return Padding(
      padding: const .fromLTRB(16, 4, 16, 8),
      child: Material(
        key: const ValueKey('settings-status-card'),
        color: error ? colors.errorContainer : colors.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: .circular(16),
          side: BorderSide(color: foreground.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const .symmetric(horizontal: 16, vertical: 8),
          child: SettingsRowLayout(
            left: Row(
              mainAxisSize: .min,
              children: [
                Icon(icon, color: foreground, size: 24),
                const SizedBox(width: 12),
                Flexible(child: label),
              ],
            ),
            right: buttons,
          ),
        ),
      ),
    );
  }
}

class _RestartNotice extends StatelessWidget {
  const _RestartNotice(this.controller, this.navigatorKey);
  final DateTimeController controller;
  final GlobalKey<NavigatorState>? navigatorKey;
  @override
  Widget build(BuildContext context) => _StatusCard(
    icon: Icons.restart_alt_rounded,
    title: 'Restart to apply settings',
    message: '',
    actions: [
      TextButton(
        onPressed: controller.isBusy ? null : () => controller.deferRestart(),
        child: const Text('Later'),
      ),
      FilledButton.icon(
        onPressed: controller.isBusy
            ? null
            : () async {
                final confirmed = await showDialog<bool>(
                  context:
                      navigatorKey?.currentState?.overlay?.context ?? context,
                  builder: (context) => AlertDialog(
                    title: const Text('Restart now?'),
                    content: const Text(
                      'Save your work before restarting the system.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Restart'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    await controller.restart();
                  } catch (_) {}
                }
              },
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text('Restart now'),
      ),
    ],
  );
}
