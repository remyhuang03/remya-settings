import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/presentation/settings_widgets.dart';
import '../application/updates_controller.dart';

/// Active hours: automatic updates wait until they end.
class ActiveHoursPage extends StatefulWidget {
  const ActiveHoursPage({super.key, required this.controller});
  final UpdatesController controller;
  @override
  State<ActiveHoursPage> createState() => _ActiveHoursPageState();
}

class _ActiveHoursPageState extends State<ActiveHoursPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  Future<void> _choose(String id, String current) async {
    final parts = current.split(':');
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (time != null) {
      await widget.controller.set(
        id,
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final schedule = controller.schedule;
      final editable = !controller.pending && schedule['editable'] != false;
      Widget row(String id, String label, String key, String fallback) {
        final value = schedule[key] as String? ?? fallback;
        return SettingRow(
          id: id,
          label: Text(label),
          control: OutlinedButton.icon(
            onPressed: editable ? () => _choose(id, value) : null,
            icon: const Icon(Icons.schedule_rounded),
            label: Text('$value (local time)'),
          ),
        );
      }

      return Column(
        crossAxisAlignment: .stretch,
        children: [
          SettingsSurface(
            padding: .zero,
            child: Column(
              children: [
                row(
                  activeHoursStartSettingId,
                  'Start time',
                  'active_start',
                  '08:00',
                ),
                row(activeHoursEndSettingId, 'End time', 'active_end', '23:00'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Automatic updates start when your active hours end. They run during active hours only to catch up after a missed inactive period, for example when the computer was off. Active hours may cross midnight; start and end must differ.',
          ),
          if (controller.errorMessage case final error?)
            Padding(
              padding: const .only(top: 12),
              child: Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}
