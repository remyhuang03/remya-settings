import 'package:material_ui/material_ui.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_content.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../../settings/application/feature_options_controller.dart';

/// Service values for each catalog option, in the catalog's option order.
const choiceValues = <String, List<Object>>{
  'mouse.primary-button': [false, true],
  'mouse.acceleration': ['adaptive', 'flat'],
  'mouse.focus-follows': [1, 2, 0, 3],
  'mouse.discrete-scroll': [1, 0, 2],
  'mouse.scroll-outside': [1, 0, 2, 3],
  'touchpad.tap-buttons': ['lrm', 'lmr'],
  'touchpad.drag-lock': [0, 1, 2],
  'touchpad.click-method': [false, true],
  'touchpad.three-finger-drag': [0, 1, 2],
  'keyboard-shortcuts.workspace-back-and-forth': [0, 1, 2],
  'background.blur-variant': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
  'multitasking.layout': ['dwindle', 'master', 'scrolling', 'monocle'],
  'multitasking.resize-corner': [0, 1, 2, 3, 4],
  'cursor.warp-on-change-workspace': [0, 1, 2],
  // `no_hardware_cursors`: 2 decides automatically, 0 uses hardware cursors.
  'cursor.hardware': [2, 0, 1],
};

/// Slider range, step and readout; the service accepts the wider Hyprland range.
typedef SliderShape = ({
  double min,
  double max,
  double step,
  String Function(double) text,
});

final sliderShapes = <String, SliderShape>{
  'mouse.pointer-speed': (
    min: -1,
    max: 1,
    step: 0.05,
    text: (v) =>
        v == 0 ? 'Default' : '${v > 0 ? '+' : ''}${(v * 100).round()}%',
  ),
  'mouse.scroll-speed': (
    min: 0.1,
    max: 3,
    step: 0.05,
    text: (v) => '${v.toStringAsFixed(2)}×',
  ),
  'touchpad.scroll-speed': (
    min: 0.1,
    max: 3,
    step: 0.05,
    text: (v) => '${v.toStringAsFixed(2)}×',
  ),
  'touchpad.swipe-distance': (
    min: 100,
    max: 1500,
    step: 50,
    text: (v) => '${v.round()} px',
  ),
  'touchpad.swipe-cancel-ratio': (
    min: 0,
    max: 1,
    step: 0.05,
    text: (v) => '${(v * 100).round()}%',
  ),
  'touchpad.swipe-min-speed': (
    min: 0,
    max: 200,
    step: 5,
    text: (v) => '${v.round()}',
  ),
  'keyboard-shortcuts.scroll-delay': (
    min: 0,
    max: 2000,
    step: 50,
    text: (v) => '${v.round()} ms',
  ),
  'background.blur-size': (
    min: 1,
    max: 30,
    step: 1,
    text: (v) => '${v.round()} px',
  ),
  'background.blur-passes': (
    min: 1,
    max: 6,
    step: 1,
    text: (v) => '${v.round()}',
  ),
  'background.blur-noise': (min: 0, max: 0.2, step: 0.005, text: _decimal),
  'background.blur-contrast': (min: 0, max: 2, step: 0.05, text: _decimal),
  'background.blur-brightness': (min: 0, max: 2, step: 0.05, text: _decimal),
  'background.blur-vibrancy': (min: 0, max: 1, step: 0.05, text: _decimal),
  'multitasking.gaps-in': (min: 0, max: 40, step: 1, text: _pixels),
  'multitasking.gaps-out': (min: 0, max: 80, step: 1, text: _pixels),
  'multitasking.border-size': (min: 0, max: 10, step: 1, text: _pixels),
  'multitasking.snap-window-gap': (min: 0, max: 50, step: 1, text: _pixels),
  'multitasking.snap-monitor-gap': (min: 0, max: 50, step: 1, text: _pixels),
  'multitasking.border-grab-area': (min: 0, max: 50, step: 1, text: _pixels),
  'multitasking.float-gaps': (min: 0, max: 80, step: 1, text: _pixels),
  'multitasking.gaps-workspaces': (min: 0, max: 100, step: 5, text: _pixels),
  'cursor.inactive-timeout': (
    min: 0,
    max: 20,
    step: 1,
    text: (v) => v == 0 ? 'Never' : '${v.round()} s',
  ),
};

String _pixels(double v) => '${v.round()} px';

String _decimal(double v) => v.toStringAsFixed(2);

/// Readable text of a stored value, for rows and the conflict summary.
String describeValue(SettingSpec setting, Object? value) {
  if (value == null) return 'Unknown';
  if (choiceValues[setting.id] case final values?) {
    final index = values.indexOf(value);
    if (index >= 0) return setting.options[index];
    if (value == '') return 'Device default';
  }
  if (sliderShapes[setting.id] case final shape?) {
    if (value is List) return _sides(value);
    return value is num ? shape.text(value.toDouble()) : '$value';
  }
  return switch (value) {
    true => 'On',
    false => 'Off',
    _ => '$value',
  };
}

/// A gap whose sides differ, in CSS order.
String _sides(List<Object?> sides) =>
    'Top ${sides[0]}, right ${sides[1]}, bottom ${sides[2]}, left ${sides[3]} px';

/// Builds the rows of the input pages from catalog specs and the shared controller.
class InputRows {
  InputRows(this.context, this.controller, this.dragging, this.onDrag);
  final BuildContext context;
  final FeatureOptionsController controller;

  /// Slider positions while a thumb is held; only the release writes, since each
  /// write rewrites the Hyprland file and reloads the compositor.
  final Map<String, double> dragging;
  final void Function(String id, double? value) onDrag;

  TextTheme get _text => Theme.of(context).textTheme;

  Widget _label(SettingSpec setting, String? subtitle) => Column(
    crossAxisAlignment: .start,
    spacing: 4,
    children: [
      Text(setting.title, style: _text.bodyLarge),
      if (subtitle != null) Text(subtitle, style: _text.bodySmall),
    ],
  );

  Widget build(SettingSpec setting, {String? subtitle}) {
    final enabled = controller.canChange;
    final value = controller.option(setting.id);
    final Widget control;
    if (choiceValues[setting.id] case final values?) {
      control =
          values.length <= 3 && setting.options.every((o) => o.length <= 14)
          ? SegmentedButton<Object>(
              key: ValueKey('${setting.id}-segments'),
              segments: [
                for (var i = 0; i < values.length; i++)
                  ButtonSegment(
                    value: values[i],
                    label: Text(setting.options[i]),
                  ),
              ],
              selected: {if (value != null && values.contains(value)) value},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: enabled
                  ? (next) {
                      if (next.isNotEmpty) {
                        controller.set(setting.id, next.first);
                      }
                    }
                  : null,
            )
          : DropdownMenu<Object>(
              key: ValueKey('${setting.id}-$value'),
              width: 260,
              enabled: enabled,
              initialSelection: values.contains(value) ? value : null,
              hintText: describeValue(setting, value),
              dropdownMenuEntries: [
                for (var i = 0; i < values.length; i++)
                  DropdownMenuEntry(
                    value: values[i],
                    label: setting.options[i],
                  ),
              ],
              onSelected: (next) {
                if (next != null) controller.set(setting.id, next);
              },
            );
    } else if (sliderShapes[setting.id] case final shape?) {
      // A gap with different sides shows them; moving the slider evens them out.
      final sides = value is List ? value : null;
      final numeric = sides == null ? value as num? : sides.first as num?;
      final current = dragging[setting.id] ?? (numeric ?? shape.min).toDouble();
      final shown = current.clamp(shape.min, shape.max).toDouble();
      final integer = value is int || sides != null;
      subtitle ??= sides != null && !dragging.containsKey(setting.id)
          ? '${_sides(sides)}. Moving the slider sets every side.'
          : shape.text(current);
      control = SizedBox(
        width: 260,
        child: Slider(
          key: ValueKey('${setting.id}-slider'),
          value: shown,
          min: shape.min,
          max: shape.max,
          divisions: ((shape.max - shape.min) / shape.step).round(),
          label: shape.text(shown),
          onChanged: enabled ? (next) => onDrag(setting.id, next) : null,
          onChangeEnd: enabled
              ? (next) {
                  onDrag(setting.id, null);
                  controller.set(
                    setting.id,
                    integer
                        ? next.round()
                        : double.parse(next.toStringAsFixed(3)),
                  );
                }
              : null,
        ),
      );
    } else {
      control = Switch(
        key: ValueKey('${setting.id}-switch'),
        value: value == true,
        onChanged: enabled ? (next) => controller.set(setting.id, next) : null,
      );
    }
    return SettingRow(
      id: setting.id,
      label: _label(setting, subtitle),
      control: control,
    );
  }

  /// Read-only list of the devices a page's settings apply to.
  Widget devices(SettingSpec setting, List<String> names, String empty) =>
      SettingRow(
        id: setting.id,
        label: Column(
          crossAxisAlignment: .start,
          spacing: 8,
          children: [
            Text(setting.title, style: _text.bodyLarge),
            if (names.isEmpty)
              Text(empty, style: _text.bodySmall)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final name in names) Chip(label: Text(name))],
              ),
          ],
        ),
      );
}

/// The common frame of the input pages: description, errors, conflict and sections.
class InputPageFrame extends StatelessWidget {
  const InputPageFrame({
    super.key,
    required this.catalog,
    required this.page,
    required this.controller,
    required this.hero,
    required this.controlBuilder,
    this.isVisible,
    this.conflictTitle,
    this.footer = const [],
  });
  final SettingsCatalog catalog;
  final SettingsPageSpec page;
  final FeatureOptionsController controller;
  final Widget hero;
  final String? conflictTitle;

  /// Shown after the sections, such as links to related pages.
  final List<Widget> footer;
  final Widget Function(SettingSpec) controlBuilder;
  final bool Function(SettingSpec)? isVisible;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      Text(page.description, style: Theme.of(context).textTheme.bodyLarge),
      const SizedBox(height: 12),
      if (controller.errorMessage case final error?)
        SettingsErrorCard(message: error, onRetry: controller.reload),
      // Placeholder values before the first read would look like device state.
      if (!controller.isLoaded)
        const Padding(
          padding: .all(48),
          child: Center(child: CircularProgressIndicator()),
        )
      else ...[
        if (controller.writeBlocked case final reason?)
          SettingsErrorCard(message: reason, onRetry: controller.reload),
        if (controller.hasConflict)
          InputConflictCard(
            controls: catalog.pages.expand((p) => p.controls),
            controller: controller,
            title: conflictTitle ?? 'Input settings differ from saved Settings',
          ),
        hero,
        for (final section in page.sections)
          SettingsSectionCard(
            section,
            onPageRow: (_) {},
            pageRows: const {},
            controlBuilder: controlBuilder,
            isVisible: isVisible,
          ),
        ...footer,
      ],
    ],
  );
}

/// Saved and system values of every differing option, with both resolutions.
class InputConflictCard extends StatelessWidget {
  const InputConflictCard({
    super.key,
    required this.controls,
    required this.controller,
    this.title = 'Input settings differ from saved Settings',
  });
  final Iterable<SettingSpec> controls;
  final FeatureOptionsController controller;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ids = (controller.state['conflicts'] as List? ?? []).cast<String>();
    final system = controller.state['system'] as Map? ?? {};
    final saved = controller.state['saved'] as Map? ?? {};
    final specs = {for (final c in controls) c.id: c};
    final lines = [
      for (final id in ids)
        if (id == 'keyboard-shortcuts')
          'Custom and turned-off shortcuts differ from input.lua'
        else if (specs[id] case final spec?)
          '${spec.title}: system ${describeValue(spec, system[id])}, '
              'Settings ${describeValue(spec, saved[id])}',
    ];
    final busy = controller.isBusy;
    return Padding(
      padding: const .only(bottom: 12),
      child: SettingsSurface(
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: 12,
          children: [
            Row(
              spacing: 16,
              children: [
                Icon(Icons.warning_amber_rounded, color: colors.tertiary),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(title, style: text.titleSmall),
                  ),
                ),
              ],
            ),
            for (final line in lines) Text(line, style: text.bodySmall),
            Wrap(
              alignment: .end,
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(
                  onPressed: busy ? null : () => controller.resolve('system'),
                  child: const Text('Use system configuration'),
                ),
                FilledButton.tonal(
                  onPressed: busy ? null : () => controller.resolve('settings'),
                  child: const Text('Apply Settings configuration'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded card holding a page's illustration and its caption.
class InputHero extends StatelessWidget {
  const InputHero({super.key, required this.child, required this.caption});
  final Widget child;
  final String caption;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const .only(bottom: 8),
    child: SettingsSurface(
      child: Column(
        spacing: 12,
        children: [
          child,
          Text(
            caption,
            textAlign: .center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}
