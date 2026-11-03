import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/presentation/settings_list.dart';
import '../../settings/presentation/settings_row_layout.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/updates_controller.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key, required this.controller});
  final UpdatesController controller;
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final value = controller.value;
      final disabled =
          !controller.available ||
          controller.pending ||
          controller.workInProgress;
      final packages = controller.packages;
      final output = controller.output.reversed.toList();
      final phase = switch (value['phase']) {
        'checking' => 'Checking repository and AUR updates',
        'upgrading' => 'Upgrading packages (attempt ${value['attempt']})',
        'retrying' => 'Waiting to retry (attempt ${value['attempt']})',
        'completed' =>
          value['kind'] == 'check'
              ? 'Update check completed'
              : value['kind'] == 'scheduled'
              ? 'Automatic update completed'
              : 'Update completed',
        'failed' => 'Update operation failed',
        _ =>
          controller.workInProgress
              ? 'Updates paused (work in progress)'
              : 'Ready to check for updates',
      };
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          SettingsSurface(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                if (controller.workInProgress) ...[
                  const Align(
                    alignment: .centerLeft,
                    child: Chip(
                      avatar: Icon(Icons.construction_rounded),
                      label: Text('Work in progress'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value['reason'] as String? ??
                        'Package updates are incomplete and unverified.',
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Execution is disabled. Saved schedules are preserved and paused; existing status and output remain available for inspection.',
                  ),
                  const SizedBox(height: 16),
                ],
                SettingsRowLayout(
                  key: const ValueKey('updates-status-actions'),
                  left: Row(
                    mainAxisSize: .min,
                    children: [
                      if (controller.busy)
                        const Padding(
                          padding: .only(right: 16),
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else
                        const Padding(
                          padding: .only(right: 16),
                          child: Icon(Icons.system_update_alt_rounded),
                        ),
                      Flexible(child: Text(phase)),
                    ],
                  ),
                  right: Wrap(
                    alignment: .end,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (controller.canInstall)
                        OutlinedButton.icon(
                          onPressed: disabled || controller.busy
                              ? null
                              : () => controller.set(
                                  updatesCheckSettingId,
                                  'check',
                                ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check for updates'),
                        )
                      else
                        FilledButton.icon(
                          onPressed: disabled || controller.busy
                              ? null
                              : () => controller.set(
                                  updatesCheckSettingId,
                                  'check',
                                ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check for updates'),
                        ),
                      if (controller.canInstall)
                        FilledButton.icon(
                          onPressed:
                              disabled ||
                                  controller.busy ||
                                  !controller.authorized
                              ? null
                              : () => controller.set(
                                  updatesUpgradeSettingId,
                                  'upgrade',
                                ),
                          icon: const Icon(Icons.downloading_rounded),
                          label: const Text('Update now'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  controller.workInProgress
                      ? 'Checks, installations and scheduled runs are unavailable.'
                      : 'Repository and AUR packages are updated with yay. The operation continues in the Settings service when this window is closed.',
                ),
                if (!controller.authorized && !controller.workInProgress)
                  Padding(
                    padding: const .only(top: 12),
                    child: Text(
                      value['auth_error'] as String? ??
                          (value['authorizing'] == true
                              ? 'Waiting for authorization…'
                              : 'Open Settings and authorize system changes to upgrade packages.'),
                    ),
                  ),
                if (!controller.available &&
                    !controller.workInProgress &&
                    value.isNotEmpty)
                  Padding(
                    padding: const .only(top: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Unavailable: missing ${(value['missing'] as List? ?? []).join(', ')}',
                          ),
                        ),
                      ],
                    ),
                  ),
                if (controller.errorMessage case final error?)
                  Padding(
                    padding: const .only(top: 12),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _AutomaticUpdates(controller: controller),
          const SizedBox(height: 16),
          SettingsSurface(
            padding: .zero,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Include held packages'),
                  subtitle: const Text(
                    'Also upgrade the kernel, firmware, mkinitcpio and installed NVIDIA packages while its driver is loaded. This choice applies only to this session.',
                  ),
                  value: value['all'] == true,
                  onChanged: disabled || controller.busy
                      ? null
                      : (all) =>
                            controller.set(updatesIncludeHeldSettingId, '$all'),
                ),
                SwitchListTile(
                  title: const Text('Retry after failure'),
                  subtitle: const Text(
                    'Retry with a delay of 5 seconds per attempt, up to 60 seconds. Turn this off to stop future attempts; the current package transaction will finish.',
                  ),
                  value: value['retry'] == true,
                  onChanged: disabled
                      ? null
                      : (retry) =>
                            controller.set(updatesRetrySettingId, '$retry'),
                ),
              ],
            ),
          ),
          if (value['checked_at'] != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: SettingsList(
                title: '${packages.length} available updates',
                itemCount: packages.length,
                empty: const Text(
                  'No updates found in the last completed check.',
                ),
                itemBuilder: (context, index) {
                  final package = packages[index];
                  return ListTile(
                    key: ValueKey('${package['source']}:${package['name']}'),
                    title: Text('${package['name']}'),
                    subtitle: Text(
                      '${package['installed']} → ${package['available']}\n${package['source']}',
                    ),
                    trailing: package['held'] == true
                        ? const Chip(label: Text('Held'))
                        : null,
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 360,
            child: SelectionArea(
              child: SettingsList(
                title: 'Update output (newest first)',
                itemCount: output.length,
                empty: Text(
                  controller.workInProgress ? 'No recorded output.' : 'Output will appear when you check or upgrade packages.',
                ),
                itemBuilder: (context, index) => Padding(
                  padding: const .symmetric(horizontal: 20, vertical: 3),
                  child: Text(
                    output[index],
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _AutomaticUpdates extends StatelessWidget {
  const _AutomaticUpdates({required this.controller});
  final UpdatesController controller;

  Future<void> _chooseTime(BuildContext context) async {
    final current = (controller.schedule['time'] as String? ?? '03:00').split(
      ':',
    );
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(current[0]),
        minute: int.parse(current[1]),
      ),
    );
    if (time != null) {
      await controller.set(
        updatesDailyTimeSettingId,
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = controller.schedule;
    final enabled = schedule['enabled'] == true;
    final error = schedule['error'] as String?;
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          SwitchListTile(
            contentPadding: .zero,
            title: const Text('Automatic updates'),
            subtitle: const Text(
              'Check and install eligible updates daily at the chosen local time. Off by default.',
            ),
            value: enabled,
            onChanged:
                controller.pending ||
                    !controller.available ||
                    controller.workInProgress ||
                    schedule['editable'] == false
                ? null
                : (enabled) =>
                      controller.set(updatesAutomaticSettingId, '$enabled'),
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            SettingRow(
              id: 'updates-daily-time',
              label: const Text('Daily update time'),
              control: OutlinedButton.icon(
                onPressed:
                    controller.pending ||
                        !controller.available ||
                        controller.workInProgress ||
                        schedule['editable'] == false
                    ? null
                    : () => _chooseTime(context),
                icon: const Icon(Icons.schedule_rounded),
                label: Text('${schedule['time']} (local time)'),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'The Settings service must remain running with system changes authorized. Closing the window keeps it running. Missed times are skipped; reopening and authorizing Settings will not start a missed update. Scheduled runs always retain the default kernel, firmware and NVIDIA holds. The current Retry choice applies.',
            ),
          ],
          if (schedule['notice'] case final String notice)
            Padding(padding: const .only(top: 12), child: Text(notice)),
          if (error != null)
            Padding(
              padding: const .only(top: 12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
