import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:material_ui/material_ui.dart';

/// The current color as a swatch; the picker applies only a confirmed choice.
///
/// `#rrggbb` values stay opaque; `#rrggbbaa` values also offer an opacity slider.
class ColorButton extends StatelessWidget {
  const ColorButton({
    super.key,
    required this.color,
    required this.title,
    required this.onChanged,
  });
  final String? color;
  final String title;
  final ValueChanged<String>? onChanged;

  bool get _alpha => color?.length == 9;

  static Color? parse(String? hex) => switch (hex?.length) {
    7 => Color(int.parse(hex!.substring(1), radix: 16) | 0xff000000),
    9 => Color(
      int.parse(hex!.substring(7), radix: 16) << 24 |
          int.parse(hex.substring(1, 7), radix: 16),
    ),
    _ => null,
  };

  String _hex(Color color) {
    final argb = color.toARGB32();
    final rgb = (argb & 0xffffff).toRadixString(16).padLeft(6, '0');
    return _alpha
        ? '#$rgb${(argb >>> 24).toRadixString(16).padLeft(2, '0')}'
        : '#$rgb';
  }

  Future<void> _pick(BuildContext context) async {
    var picked = parse(color) ?? Colors.black;
    final confirmed = await ColorPicker(
      color: picked,
      onColorChanged: (next) => picked = next,
      pickersEnabled: const {
        ColorPickerType.primary: true,
        ColorPickerType.accent: false,
        ColorPickerType.wheel: true,
      },
      enableShadesSelection: true,
      enableOpacity: _alpha,
      showColorCode: true,
      colorCodeHasColor: true,
      heading: Text(title, style: Theme.of(context).textTheme.titleMedium),
      subheading: const Text('Shades'),
      wheelSubheading: const Text('Shades'),
      opacitySubheading: const Text('Opacity'),
    ).showPickerDialog(context);
    if (confirmed) onChanged?.call(_hex(picked));
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: onChanged == null ? null : () => _pick(context),
    icon: Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: parse(color),
        shape: .circle,
        border: .all(color: Theme.of(context).colorScheme.outline),
      ),
    ),
    label: Text(color ?? 'Unknown'),
  );
}
