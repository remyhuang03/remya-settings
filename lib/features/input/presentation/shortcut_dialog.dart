import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../settings/application/feature_options_controller.dart';
import 'shortcut_model.dart';

/// XKB keycodes by Flutter physical key; Hyprland resolves them in the active layout.
final _xkbCodes = {
  for (final entry in kLinuxToPhysicalKey.entries) entry.value: entry.key,
};

final _modifierKeys = {
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.superKey,
  LogicalKeyboardKey.hyper,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.fn,
};

/// A custom shortcut being created or edited.
typedef ShortcutDraft = ({
  String keys,
  String action,
  String command,
  String description,
});

/// Opens the editor; [initial] edits a custom shortcut, [keys] proposes a combination.
Future<void> showShortcutDialog(
  BuildContext context,
  FeatureOptionsController controller, {
  ShortcutDraft? initial,
  String? keys,
}) => showDialog(
  context: context,
  builder: (_) => _ShortcutDialog(
    controller: controller,
    initial: initial,
    keys: keys ?? initial?.keys,
  ),
);

class _ShortcutDialog extends StatefulWidget {
  const _ShortcutDialog({required this.controller, this.initial, this.keys});
  final FeatureOptionsController controller;
  final ShortcutDraft? initial;
  final String? keys;

  @override
  State<_ShortcutDialog> createState() => _ShortcutDialogState();
}

class _ShortcutDialogState extends State<_ShortcutDialog> {
  final _recorder = FocusNode(debugLabel: 'shortcut recorder');
  late final _command = TextEditingController(text: widget.initial?.command);
  late final _description = TextEditingController(
    text: widget.initial?.description,
  );
  late String _action = widget.initial?.action ?? 'command';
  Map<String, dynamic>? _lookup;
  Set<String> _held = {};
  bool _recording = false;
  String? _error;

  FeatureOptionsController get _controller => widget.controller;
  SettingsClient get _client => _controller.client;
  List<LiveShortcut> get _conflicts => [
    for (final c in _lookup?['conflicts'] as List? ?? [])
      if (c['keys'] != widget.initial?.keys) LiveShortcut((c as Map).cast()),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.keys case final keys?) unawaited(_resolve(keys));
  }

  @override
  void dispose() {
    if (_recording) {
      unawaited(
        _client.recordShortcut(false).catchError((_) => <String, dynamic>{}),
      );
    }
    _recorder.dispose();
    _command.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _resolve(String keys) async {
    try {
      final lookup = await _client.lookupShortcut(keys);
      if (mounted) {
        setState(() {
          _lookup = lookup;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _lookup = null;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _setRecording(bool recording) async {
    try {
      await _client.recordShortcut(recording);
      if (!mounted) return;
      setState(() {
        _recording = recording;
        _held = {};
      });
      if (recording) _recorder.requestFocus();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  Set<String> _modifiers() {
    final keyboard = HardwareKeyboard.instance;
    return {
      if (keyboard.isMetaPressed ||
          keyboard.isLogicalKeyPressed(LogicalKeyboardKey.superKey))
        'SUPER',
      if (keyboard.isControlPressed) 'CTRL',
      if (keyboard.isAltPressed) 'ALT',
      if (keyboard.isShiftPressed) 'SHIFT',
    };
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (!_recording) return .ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape && _modifiers().isEmpty) {
      // The recording submap's Escape bind has already restored compositor shortcuts.
      if (event is KeyDownEvent) unawaited(_setRecording(false));
      return .handled;
    }
    if (_modifierKeys.contains(event.logicalKey)) {
      setState(() => _held = _modifiers());
      return .handled;
    }
    final code = _xkbCodes[event.physicalKey];
    if (event is! KeyDownEvent || code == null) return .handled;
    final keys = [
      ...{'SUPER', 'CTRL', 'ALT', 'SHIFT'}.where(_modifiers().contains),
      'code:$code',
    ].join(' + ');
    unawaited(_setRecording(false).then((_) => _resolve(keys)));
    return .handled;
  }

  Future<void> _save() async {
    final keys = _lookup?['keys'] as String?;
    if (keys == null) return;
    final saved = await _controller.set(addShortcutId, {
      'keys': keys,
      'action': _action,
      if (_action == 'command') 'command': _command.text,
      'description': _description.text,
      'replace': _conflicts.isNotEmpty,
      'previous': ?widget.initial?.keys,
    });
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = _controller.errorMessage);
    }
  }

  Widget _recorderField() {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final Widget content;
    if (_recording) {
      content = _held.isEmpty
          ? Text('Press the new key combination', style: text.bodyLarge)
          : Keycaps(modifiers: _held.toList(), label: '…');
    } else if (_lookup case final lookup?) {
      content = Keycaps(
        modifiers: (lookup['modifiers'] as List).cast(),
        label: lookup['label'] as String,
      );
    } else {
      content = Text('No key combination yet', style: text.bodyLarge);
    }
    return Focus(
      focusNode: _recorder,
      onKeyEvent: _onKey,
      child: Container(
        padding: const .all(16),
        decoration: BoxDecoration(
          color: _recording
              ? colors.primaryContainer
              : colors.surfaceContainerHigh,
          borderRadius: .circular(16),
        ),
        child: Row(
          spacing: 12,
          children: [
            Icon(
              _recording
                  ? Icons.radio_button_checked_rounded
                  : Icons.keyboard_rounded,
              color: _recording ? colors.primary : colors.onSurfaceVariant,
            ),
            Expanded(child: Semantics(liveRegion: true, child: content)),
            FilledButton.tonal(
              key: const ValueKey('shortcut-record'),
              onPressed: () => _setRecording(!_recording),
              child: Text(
                _recording
                    ? 'Stop'
                    : (_lookup == null ? 'Record' : 'Record again'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final conflicts = _conflicts;
    final command = _action == 'command';
    final ready =
        _lookup != null &&
        !_recording &&
        (!command || _command.text.trim().isNotEmpty);
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add a shortcut' : 'Edit shortcut'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            spacing: 16,
            children: [
              _recorderField(),
              if (_recording)
                Text(
                  'Other shortcuts are paused while recording. Press Esc to cancel.',
                  style: text.bodySmall,
                ),
              if (conflicts.isNotEmpty)
                Row(
                  crossAxisAlignment: .start,
                  spacing: 12,
                  children: [
                    Icon(Icons.swap_horiz_rounded, color: colors.tertiary),
                    Expanded(
                      child: Text(
                        'Already used for ${conflicts.map((c) => c.title).join(', ')}. '
                        'Saving turns that off and uses this shortcut instead.',
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              DropdownMenu<String>(
                key: const ValueKey('shortcut-action'),
                label: const Text('Action'),
                expandedInsets: .zero,
                initialSelection: _action,
                dropdownMenuEntries: [
                  for (final MapEntry(:key, :value) in shortcutActions.entries)
                    DropdownMenuEntry(value: key, label: value),
                ],
                onSelected: (next) => setState(() => _action = next ?? _action),
              ),
              if (command)
                TextField(
                  key: const ValueKey('shortcut-command'),
                  controller: _command,
                  decoration: const InputDecoration(
                    labelText: 'Command',
                    hintText: 'For example: foot',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              TextField(
                key: const ValueKey('shortcut-description'),
                controller: _description,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                ),
              ),
              if (_error case final error?)
                Text(
                  error,
                  style: text.bodyMedium?.copyWith(color: colors.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('shortcut-save'),
          onPressed: ready && !_controller.isBusy ? _save : null,
          child: Text(conflicts.isEmpty ? 'Save' : 'Replace'),
        ),
      ],
    );
  }
}
