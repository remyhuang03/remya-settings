import 'package:material_ui/material_ui.dart';

/// One live combination as the service groups it, with display helpers.
extension type LiveShortcut(Map<String, dynamic> raw) {
  String get keys => raw['keys'] as String;
  List<String> get modifiers =>
      (raw['modifiers'] as List? ?? []).cast<String>();
  String get label => raw['label'] as String? ?? '';
  int? get code => raw['code'] as int?;
  String get submap => raw['submap'] as String? ?? '';
  bool get custom => raw['custom'] == true;
  bool get mouse => raw['mouse'] == true;
  String get description => raw['description'] as String? ?? '';
  List<String> get actions => (raw['actions'] as List? ?? []).cast<String>();

  (String, String) get _split {
    final at = description.indexOf(': ');
    return at > 0 && at < 24
        ? (description.substring(0, at), description.substring(at + 2))
        : ('', description);
  }

  String get category => switch (_split.$1) {
    '' when mouse => 'Mouse',
    '' => 'Other',
    final name => name,
  };
  String get title => _split.$2.isEmpty ? actions.join(', ') : _split.$2;
}

const modifierLabels = {
  'SUPER': 'Super',
  'CTRL': 'Ctrl',
  'ALT': 'Alt',
  'SHIFT': 'Shift',
};

/// The service's actions for custom shortcuts, with their labels.
const shortcutActions = {
  'command': 'Run a command',
  'close': 'Close window',
  'float': 'Float or tile window',
  'fullscreen': 'Fullscreen',
  'maximize': 'Maximize',
  'pin': 'Pin window',
  'scratchpad': 'Show or hide the scratchpad',
};

/// A key combination drawn as keycaps.
class Keycaps extends StatelessWidget {
  const Keycaps({super.key, required this.modifiers, required this.label});
  final List<String> modifiers;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium;
    Widget cap(String text) => Container(
      padding: const .symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: .circular(8),
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant, width: 2),
        ),
      ),
      child: Text(text, style: style),
    );
    return Semantics(
      label: [
        ...modifiers.map((m) => modifierLabels[m] ?? m),
        label,
      ].join(' plus '),
      excludeSemantics: true,
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: .center,
        children: [
          for (final m in modifiers) cap(modifierLabels[m] ?? m),
          cap(label),
        ],
      ),
    );
  }
}
