import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../../integration/settings_icon_cache.dart';

/// GTK resolves the desktop's current icon theme and decodes raster/SVG icons.
class ApplicationIcon extends StatelessWidget {
  const ApplicationIcon({super.key, required this.icon, this.size = 40});
  final String? icon;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ListenableBuilder(
      listenable: settingsIcons,
      builder: (context, _) => FutureBuilder<Uint8List?>(
        future: icon == null
            ? null
            : settingsIcons.get(
                icon!,
                () => settingsIconChannel.invokeMethod<Uint8List>(
                  'applicationIcon',
                  icon,
                ),
                fileBacked: icon!.contains('/'),
              ),
        builder: (context, snapshot) => snapshot.data == null
            ? Icon(Icons.apps_rounded, size: size * 0.7)
            : Image.memory(
                snapshot.data!,
                width: size,
                height: size,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.apps_rounded, size: size * 0.7),
              ),
      ),
    ),
  );
}
