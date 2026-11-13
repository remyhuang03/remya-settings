import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';

/// Window and workspace motion, motion blur and wobbly windows.
class AnimationsPage extends StatefulWidget {
  const AnimationsPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<AnimationsPage> createState() => _AnimationsPageState();
}

class _AnimationsPageState extends State<AnimationsPage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: 'desktop',
  )..reload();
  final _dragging = <String, double>{};

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _on(String id) => _controller.option(id) == true;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final rows = InputRows(
        context,
        _controller,
        _dragging,
        (id, value) => setState(
          () => value == null ? _dragging.remove(id) : _dragging[id] = value,
        ),
      );
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        conflictTitle: 'Animation settings differ from saved Settings',
        hero: const SizedBox.shrink(),
        isVisible: (setting) => switch (setting.id) {
          'animations.motion-blur-samples' => _on('animations.motion-blur'),
          _ when setting.id.startsWith('animations.wobble-') => _on(
            'animations.wobble',
          ),
          _ => true,
        },
        controlBuilder: (setting) => switch (setting.id) {
          'animations.enabled' => rows.build(
            setting,
            subtitle: 'Windows, workspaces and panels move and fade smoothly',
          ),
          'animations.workspace-wraparound' => rows.build(
            setting,
            subtitle:
                'Going from the last workspace to the first slides forward '
                'instead of back',
          ),
          'animations.motion-blur' => rows.build(
            setting,
            subtitle: 'Moving and resizing windows leave a short blur trail',
          ),
          'animations.motion-blur-samples' => rows.build(
            setting,
            subtitle: 'More samples look smoother and use more graphics power',
          ),
          'animations.wobble' => rows.build(
            setting,
            subtitle: 'Windows flex like jelly while you move or resize them',
          ),
          'animations.wobble-stiffness' => rows.build(
            setting,
            subtitle: 'Stiffer windows spring back faster',
          ),
          'animations.wobble-damping' => rows.build(
            setting,
            subtitle: 'More damping stops the wobble sooner',
          ),
          'animations.wobble-mass' => rows.build(
            setting,
            subtitle: 'Heavier windows swing wider and slower',
          ),
          'animations.wobble-mesh' => rows.build(
            setting,
            subtitle: 'Finer meshes bend more smoothly and cost more to draw',
          ),
          'animations.wobble-value-epsilon' ||
          'animations.wobble-velocity-epsilon' => rows.build(
            setting,
            subtitle: 'Below this the window counts as still',
          ),
          _ => rows.build(setting),
        },
      );
    },
  );
}
