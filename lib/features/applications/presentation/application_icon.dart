import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// GTK resolves the desktop's current icon theme and decodes raster/SVG icons.
class ApplicationIcon extends StatelessWidget {
  const ApplicationIcon({super.key, required this.icon, this.size = 40});
  final String? icon;
  final double size;
  static final _icons = <String, Future<Uint8List?>>{};
  static const _channel = MethodChannel('top.remya.paths');
  static Future<Uint8List?> _load(String icon) async {
    try {
      return await _channel.invokeMethod<Uint8List>('applicationIcon', icon);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: FutureBuilder<Uint8List?>(
      future: icon == null
          ? null
          : _icons.putIfAbsent(icon!, () => _load(icon!)),
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
  );
}
