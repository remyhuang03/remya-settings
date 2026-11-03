import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:material_ui/material_ui.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/background_controller.dart';

const _imageTypes = XTypeGroup(
  label: 'Images',
  mimeTypes: [
    'image/png',
    'image/jpeg',
    'image/webp',
    'image/bmp',
    'image/svg+xml',
  ],
);
const _videoTypes = XTypeGroup(
  label: 'Videos',
  mimeTypes: ['video/mp4', 'video/webm', 'video/x-matroska', 'video/quicktime'],
);
const _fitLabels = {
  'cover': 'Cover',
  'contain': 'Contain',
  'tile': 'Tile',
  'fill': 'Fill',
};
const _pauseLabels = {'keep': 'Keep playing', 'pause': 'Pause', 'stop': 'Stop'};

typedef BackgroundFilePicker = Future<String?> Function(bool video);

Future<String?> _pickWithDialog(bool video) async =>
    (await openFile(acceptedTypeGroups: [video ? _videoTypes : _imageTypes]))
        ?.path;

class BackgroundPage extends StatefulWidget {
  const BackgroundPage({
    super.key,
    required this.page,
    required this.controller,
    this.pickFile = _pickWithDialog,
  });
  final SettingsPageSpec page;
  final BackgroundController controller;
  final BackgroundFilePicker pickFile;

  @override
  State<BackgroundPage> createState() => _BackgroundPageState();
}

class _BackgroundPageState extends State<BackgroundPage> {
  Set<String> _selection = const {};

  BackgroundController get _controller => widget.controller;

  Set<String> get _displays => _controller.validDisplaySelection(_selection);

  /// The display whose values the page shows; the selection shares them.
  String get _shown =>
      _controller.isVideo || _displays.isEmpty ? allDisplays : _displays.first;

  /// Covering every display is "all", so displays connected later follow it too.
  Object get _request {
    final displays = _displays;
    if (_controller.isVideo ||
        displays.isEmpty ||
        displays.length == _controller.monitors.length) {
      return allDisplays;
    }
    return displays.length == 1 ? displays.first : displays.toList();
  }

  SettingSpec _setting(String id) =>
      widget.page.controls.firstWhere((setting) => setting.id == id);

  Future<void> _choose(bool video) async {
    final path = await widget.pickFile(video);
    if (path == null) return;
    await _controller.set(
      backgroundFileSettingId,
      jsonEncode({'path': path, 'display': video ? allDisplays : _request}),
    );
  }

  Future<void> _setKind(String kind) async {
    final missing = kind == 'video'
        ? _controller.video.isEmpty
        : _controller.imageFor(allDisplays) == null;
    if (missing) return _choose(kind == 'video');
    await _controller.set(backgroundKindSettingId, kind);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => Column(
      crossAxisAlignment: .stretch,
      children: [
        for (final warning in _controller.warnings) _Notice(warning),
        _Preview(path: _controller.previewOf(_controller.pathFor(_shown))),
        if (!_controller.isVideo && _controller.monitors.length > 1)
          _DisplayButtons(
            setting: _setting(backgroundDisplaySettingId),
            groups: _controller.displayGroups,
            selected: _displays,
            onPressed: (display) => setState(() {
              _selection = BackgroundController.nextDisplaySelection(
                _controller.displayGroups,
                _displays,
                display,
              );
            }),
          ),
        Padding(
          padding: const .only(top: 28, bottom: 12),
          child: Text(
            widget.page.sections.first.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SettingsSurface(padding: .zero, child: _main()),
        _advanced(),
      ],
    ),
  );

  Widget _main() {
    final enabled = _controller.canChange;
    final path = _controller.pathFor(_shown);
    final fits = _controller.isVideo
        ? (const ['cover', 'contain', 'fill'])
        : _fitLabels.keys.toList();
    return Column(
      children: [
        _Row(
          setting: _setting(backgroundKindSettingId),
          control: SegmentedButton<String>(
            key: const ValueKey('background-kind'),
            segments: const [
              ButtonSegment(
                value: 'image',
                label: Text('Image'),
                icon: Icon(Icons.image_outlined),
              ),
              ButtonSegment(
                value: 'video',
                label: Text('Video'),
                icon: Icon(Icons.movie_outlined),
              ),
            ],
            selected: {_controller.kind},
            onSelectionChanged: enabled ? (s) => _setKind(s.single) : null,
          ),
        ),
        const Divider(height: 1, indent: 20, endIndent: 20),
        _Row(
          setting: _setting(backgroundFileSettingId),
          readout: _controller.nameOf(path) ?? 'No file selected',
          control: FilledButton.icon(
            key: const ValueKey('background-browse'),
            onPressed: enabled ? () => _choose(_controller.isVideo) : null,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Browse'),
          ),
        ),
        if (path != null) ...[
          const Divider(height: 1, indent: 20, endIndent: 20),
          _Row(
            setting: _setting(backgroundFitSettingId),
            control: _Choice(
              id: 'background-fit',
              value: _controller.fitFor(_shown) ?? 'cover',
              labels: {for (final fit in fits) fit: _fitLabels[fit]!},
              onChanged: enabled
                  ? (fit) => _controller.set(
                      backgroundFitSettingId,
                      jsonEncode({'fit': fit, 'display': _request}),
                    )
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  /// Video options apply only to video, and splash options only to a visible
  /// hyprpaper; anything else is hidden rather than shown disabled.
  List<Widget> _advancedRows() {
    final enabled = _controller.canChange;
    if (_controller.isVideo) {
      return [
        _Row(
          setting: _setting(backgroundPauseSettingId),
          control: _Choice(
            id: 'background-pause',
            value: _controller.video['pause'] as String? ?? 'keep',
            labels: _pauseLabels,
            onChanged: enabled
                ? (value) => _controller.set(backgroundPauseSettingId, value)
                : null,
          ),
        ),
      ];
    }
    final splash = _controller.splash;
    final shown = splash['enabled'] == true;
    final offset = (splash['offset'] as num? ?? 20).toDouble();
    final opacity = (splash['opacity'] as num? ?? 0.8).toDouble();
    return [
      _Row(
        setting: _setting(splashSettingId),
        control: Switch(
          key: const ValueKey('background-splash'),
          value: shown,
          onChanged: enabled
              ? (value) => _controller.set(splashSettingId, '$value')
              : null,
        ),
      ),
      if (shown) ...[
        const Divider(height: 1, indent: 20, endIndent: 20),
        _Row(
          setting: _setting(splashOffsetSettingId),
          readout: '${offset.round()} px',
          control: _CommitSlider(
            key: const ValueKey('background-splash-offset'),
            value: offset,
            // A larger value set through the CLI stays representable.
            max: offset > 200 ? offset : 200,
            divisions: offset > 200 ? null : 40,
            label: (value) => '${value.round()} px',
            enabled: enabled,
            onChanged: (value) =>
                _controller.set(splashOffsetSettingId, '${value.round()}'),
          ),
        ),
        const Divider(height: 1, indent: 20, endIndent: 20),
        _Row(
          setting: _setting(splashOpacitySettingId),
          readout: opacity.toStringAsFixed(2),
          control: _CommitSlider(
            key: const ValueKey('background-splash-opacity'),
            value: opacity,
            max: 1,
            divisions: 20,
            label: (value) => value.toStringAsFixed(2),
            enabled: enabled,
            onChanged: (value) => _controller.set(
              splashOpacitySettingId,
              value.toStringAsFixed(2),
            ),
          ),
        ),
      ],
    ];
  }

  Widget _advanced() => AdvancedSection(
    storageKey: const PageStorageKey('background-advanced'),
    child: KeyedSubtree(
      key: const PageStorageKey('background-advanced-body'),
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          ..._advancedRows(),
          for (final (title, prefix) in const [
            ('Compositor background', 'background.compositor-'),
            ('Compositor blur', 'background.blur-'),
          ]) ...[
            Padding(
              padding: const .fromLTRB(20, 24, 20, 12),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final setting in widget.page.controls.where(
              (s) => s.id.startsWith(prefix),
            ))
              SettingControlTile(setting),
          ],
        ],
      ),
    ),
  );
}

/// Displays as connected buttons, with a gap between groups of different settings.
class _DisplayButtons extends StatelessWidget {
  const _DisplayButtons({
    required this.setting,
    required this.groups,
    required this.selected,
    required this.onPressed,
  });
  final SettingSpec setting;
  final List<List<String>> groups;
  final Set<String> selected;
  final ValueChanged<String> onPressed;

  Widget _button(ColorScheme colors, List<String> group, int index) {
    final display = group[index];
    final isSelected = selected.contains(display);
    return Semantics(
      selected: isSelected,
      child: FilledButton(
        key: ValueKey('background-display-$display'),
        style: FilledButton.styleFrom(
          backgroundColor: isSelected
              ? colors.primary
              : colors.secondaryContainer,
          foregroundColor: isSelected
              ? colors.onPrimary
              : colors.onSecondaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: .horizontal(
              left: .circular(index == 0 ? 24 : 8),
              right: .circular(index == group.length - 1 ? 24 : 8),
            ),
          ),
        ),
        onPressed: () => onPressed(display),
        child: Text(display),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      key: ValueKey(setting.id),
      padding: const .only(top: 16),
      child: Column(
        children: [
          Wrap(
            alignment: .center,
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final group in groups)
                Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (var i = 0; i < group.length; i++)
                      _button(colors, group, i),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            setting.reason,
            textAlign: .center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const .only(bottom: 12),
      child: Material(
        key: const ValueKey('background-warning'),
        color: colors.tertiaryContainer,
        borderRadius: .circular(16),
        child: Padding(
          padding: const .all(14),
          child: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: colors.onTertiaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: colors.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.path});
  final String? path;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Icon(
        Icons.wallpaper_outlined,
        size: 48,
        color: colors.onSurfaceVariant,
        semanticLabel: 'No background preview',
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: ClipRRect(
          borderRadius: .circular(24),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: path == null
                ? placeholder
                : Image.file(
                    File(path!),
                    key: ValueKey(path),
                    fit: .cover,
                    semanticLabel: 'Current background',
                    errorBuilder: (_, _, _) => placeholder,
                  ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.setting, required this.control, this.readout});
  final SettingSpec setting;
  final Widget control;
  final String? readout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SettingRow(
      id: setting.id,
      label: Column(
        crossAxisAlignment: .start,
        children: [
          Text(setting.title, style: text.bodyLarge),
          const SizedBox(height: 6),
          Text(setting.reason, style: text.bodySmall),
          if (readout case final readout?) ...[
            const SizedBox(height: 4),
            Text(readout, style: text.bodyMedium),
          ],
        ],
      ),
      control: Semantics(label: setting.title, child: control),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.id,
    required this.value,
    required this.labels,
    required this.onChanged,
  });
  final String id;
  final String value;
  final Map<String, String> labels;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 232,
    child: DropdownButtonFormField<String>(
      key: ValueKey('$id-$value'),
      initialValue: labels.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(borderRadius: .all(.circular(14))),
      ),
      items: [
        for (final entry in labels.entries)
          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onChanged: onChanged == null
          ? null
          : (value) {
              if (value != null) onChanged!(value);
            },
    ),
  );
}

/// Follows the drag locally and applies once, when the drag ends.
class _CommitSlider extends StatefulWidget {
  const _CommitSlider({
    super.key,
    required this.value,
    required this.max,
    required this.label,
    required this.enabled,
    required this.onChanged,
    this.divisions,
  });
  final double value;
  final double max;
  final int? divisions;
  final String Function(double) label;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<_CommitSlider> createState() => _CommitSliderState();
}

class _CommitSliderState extends State<_CommitSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final value = _dragging ?? widget.value;
    return SizedBox(
      width: 220,
      child: Slider(
        value: value,
        max: widget.max,
        divisions: widget.divisions,
        label: widget.label(value),
        onChanged: widget.enabled
            ? (next) => setState(() => _dragging = next)
            : null,
        onChangeEnd: widget.enabled
            ? (next) {
                setState(() => _dragging = null);
                widget.onChanged(next);
              }
            : null,
      ),
    );
  }
}
