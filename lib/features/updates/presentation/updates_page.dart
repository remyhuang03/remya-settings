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
      final idle = !controller.pending && !controller.busy;
      final output = controller.output.reversed.toList();
      final phase = switch (value['phase']) {
        'checking' => 'Checking for updates',
        'upgrading' => 'Upgrading packages (attempt ${value['attempt']})',
        'retrying' => 'Waiting to retry (attempt ${value['attempt']})',
        'completed' =>
          value['kind'] == 'check'
              ? 'Update check completed'
              : value['kind'] == 'scheduled'
              ? 'Automatic update completed'
              : 'Update completed',
        'failed' => 'Update operation failed',
        _ => 'Ready to check for updates',
      };
      void check() => controller.set(updatesCheckSettingId, 'check');
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          SettingsSurface(
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                SettingsRowLayout(
                  key: const ValueKey('updates-status-actions'),
                  left: Row(
                    mainAxisSize: .min,
                    children: [
                      Padding(
                        padding: const .only(right: 16),
                        child: controller.busy
                            ? const SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator(),
                              )
                            : const Icon(Icons.system_update_alt_rounded),
                      ),
                      Flexible(child: Text(phase)),
                    ],
                  ),
                  right: Wrap(
                    alignment: .end,
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      if (controller.canInstall) ...[
                        OutlinedButton.icon(
                          onPressed: idle && controller.canCheck ? check : null,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check for updates'),
                        ),
                        FilledButton.icon(
                          onPressed: idle
                              ? () => controller.set(
                                  updatesUpgradeSettingId,
                                  'upgrade',
                                )
                              : null,
                          icon: const Icon(Icons.downloading_rounded),
                          label: const Text('Update now'),
                        ),
                      ] else
                        FilledButton.icon(
                          onPressed: idle && controller.canCheck ? check : null,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Check for updates'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Repository packages are upgraded with pacman by the system updater and continue in the Settings service when this window is closed. AUR packages are only listed; update them with yay in a terminal.',
                ),
                if (value.isNotEmpty && !controller.available)
                  _Unavailable(value: value),
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
                    'Also upgrade the kernel, firmware, mkinitcpio and installed NVIDIA packages while its driver is loaded. This choice applies only to this session; automatic updates always keep them held.',
                  ),
                  value: value['all'] == true,
                  onChanged: controller.available && idle
                      ? (all) =>
                            controller.set(updatesIncludeHeldSettingId, '$all')
                      : null,
                ),
                SwitchListTile(
                  title: const Text('Retry after failure'),
                  subtitle: const Text(
                    'Retry with a delay of 5 seconds per attempt, up to 60 seconds. Turn this off to stop future attempts; the current package transaction will finish.',
                  ),
                  value: value['retry'] == true,
                  onChanged: controller.available && !controller.pending
                      ? (retry) =>
                            controller.set(updatesRetrySettingId, '$retry')
                      : null,
                ),
              ],
            ),
          ),
          if (value['checked_at'] != null) ...[
            const SizedBox(height: 16),
            _Packages(
              title: '${controller.repository.length} repository updates',
              packages: controller.repository,
              empty: 'No repository updates found in the last check.',
            ),
            if (value['aur'] == true) ...[
              const SizedBox(height: 16),
              _Packages(
                title: '${controller.aur.length} AUR updates',
                packages: controller.aur,
                empty: 'No AUR updates found in the last check.',
              ),
            ],
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 360,
            child: SelectionArea(
              child: SettingsList(
                title: 'Update output (newest first)',
                itemCount: output.length,
                empty: const Text(
                  'Output will appear when you check or upgrade packages.',
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

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.value});
  final Map<String, dynamic> value;

  @override
  Widget build(BuildContext context) {
    final setup = (value['missing'] as List? ?? const []).isEmpty;
    return Padding(
      padding: const .only(top: 12),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  value['reason'] as String? ??
                      'System updates are unavailable.',
                ),
                if (setup) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    value['install_command'] as String? ?? '',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Packages extends StatelessWidget {
  const _Packages({
    required this.title,
    required this.packages,
    required this.empty,
  });
  final String title;
  final List<Map> packages;
  final String empty;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 300,
    child: SettingsList(
      title: title,
      itemCount: packages.length,
      empty: Text(empty),
      itemBuilder: (context, index) {
        final package = packages[index];
        return ListTile(
          key: ValueKey('${package['source']}:${package['name']}'),
          title: Text('${package['name']}'),
          subtitle: Text('${package['installed']} → ${package['available']}'),
          trailing: package['held'] == true
              ? const Chip(
                  avatar: Icon(Icons.pause_circle_outline_rounded),
                  label: Text('Held'),
                )
              : null,
        );
      },
    ),
  );
}

class _AutomaticUpdates extends StatelessWidget {
  const _AutomaticUpdates({required this.controller});
  final UpdatesController controller;

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
            subtitle: Text(
              'Install eligible repository updates when your active hours end (${schedule['active_start'] ?? '08:00'} to ${schedule['active_end'] ?? '23:00'}). Change them in Active hours. Off by default.',
            ),
            value: enabled,
            onChanged: controller.pending || schedule['editable'] == false
                ? null
                : (enabled) =>
                      controller.set(updatesAutomaticSettingId, '$enabled'),
          ),
          if (enabled) ...[
            const SizedBox(height: 12),
            const Text(
              'The Settings service starts with your session and updates in the background once per inactive period. If the computer was off for a whole inactive period, the missed update runs at the next sign-in, even during active hours. Automatic updates always keep the kernel, firmware and NVIDIA packages held. The current Retry choice applies.',
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
