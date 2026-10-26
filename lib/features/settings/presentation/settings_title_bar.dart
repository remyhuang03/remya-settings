import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

class SettingsTitleBar extends StatelessWidget {
  const SettingsTitleBar({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const .symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/icons/settings.png',
                      width: 20,
                      height: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text("Remy'a Settings", overflow: .ellipsis),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: () async {
              await windowManager.close();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
    ),
  );
}
