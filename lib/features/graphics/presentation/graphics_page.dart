import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../input/presentation/input_widgets.dart';
import '../../settings/application/feature_options_controller.dart';
import '../../settings/domain/settings_catalog.dart';

/// Adaptive sync, tearing, scanout, HDR switching and X11 app scaling.
class GraphicsPage extends StatefulWidget {
  const GraphicsPage({
    super.key,
    required this.catalog,
    required this.page,
    required this.client,
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final SettingsClient client;

  @override
  State<GraphicsPage> createState() => _GraphicsPageState();
}

class _GraphicsPageState extends State<GraphicsPage> {
  late final _controller = FeatureOptionsController(
    widget.client,
    feature: 'desktop',
  )..reload();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final rows = InputRows(context, _controller, const {}, (_, _) {});
      return InputPageFrame(
        catalog: widget.catalog,
        page: widget.page,
        controller: _controller,
        conflictTitle: 'Desktop settings differ from saved Settings',
        hero: const SizedBox.shrink(),
        controlBuilder: (setting) => rows.build(
          setting,
          subtitle: switch (setting.id) {
            'graphics.allow-tearing' =>
              'Games that ask for it can skip vertical sync for lower latency',
            'graphics.direct-scanout' =>
              'A full-screen app is sent straight to the display, which '
                  'can lower latency but cause flicker on some drivers',
            'graphics.auto-hdr' =>
              'Applies when a full-screen app shows HDR content',
            'graphics.xwayland-zero-scaling' =>
              'Sharp but small on scaled displays unless the app scales '
                  'itself',
            _ => null,
          },
        ),
      );
    },
  );
}
