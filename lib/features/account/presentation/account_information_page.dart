import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:croppy/croppy.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../application/account_controller.dart';
import 'avatar_crop_controller.dart';

const _imageTypes = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp'],
);
Future<String?> _pickAvatar() async =>
    (await openFile(acceptedTypeGroups: [_imageTypes]))?.path;

class AccountInformationPage extends StatefulWidget {
  const AccountInformationPage({
    super.key,
    required this.page,
    required this.controller,
    this.pickImage = _pickAvatar,
  });
  final SettingsPageSpec page;
  final AccountController controller;
  final Future<String?> Function() pickImage;

  @override
  State<AccountInformationPage> createState() => _AccountInformationPageState();
}

class _AccountInformationPageState extends State<AccountInformationPage> {
  @override
  void initState() {
    super.initState();
    widget.controller.reload();
  }

  Future<void> _choose() async {
    try {
      final path = await widget.pickImage();
      if (path == null || !mounted) return;
      final crop = await showDialog<Map<String, double>>(
        context: context,
        builder: (_) => _AvatarCropDialog(path: path),
      );
      if (crop != null) await widget.controller.saveAvatar(path, crop);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to select avatar: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          if (controller.isBusy) const LinearProgressIndicator(),
          if (controller.errorMessage case final error?)
            SettingsErrorCard(
              message: error,
              onRetry: controller.isBusy ? null : controller.reload,
            ),
          SettingsSurface(
            child: Column(
              children: [
                _Avatar(
                  key: ValueKey(controller.value['avatar_revision']),
                  path: controller.value['avatar_path'] as String?,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey(accountAvatarSettingId),
                  onPressed: controller.isBusy ? null : _choose,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Change avatar'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Saved in Settings. This does not change your desktop account picture.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: .center,
                ),
              ],
            ),
          ),
          const SettingsSectionTitle('Account'),
          SettingsSurface(
            padding: .zero,
            child: settingsRows([
              _Readout(
                id: accountUsernameSettingId,
                title: 'Username',
                value: controller.value['username'] as String?,
              ),
              for (final setting in widget.page.controls.where(
                (s) => !const {
                  accountUsernameSettingId,
                  accountAvatarSettingId,
                }.contains(s.id),
              ))
                SettingControlTile(setting),
            ]),
          ),
        ],
      );
    },
  );
}

class _Readout extends StatelessWidget {
  const _Readout({required this.id, required this.title, required this.value});
  final String id;
  final String title;
  final String? value;
  @override
  Widget build(BuildContext context) => SettingRow(
    id: id,
    label: Column(
      crossAxisAlignment: .start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        SelectableText(
          value ?? 'Unavailable',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class _Avatar extends StatefulWidget {
  const _Avatar({super.key, this.path});
  final String? path;
  @override
  State<_Avatar> createState() => _AvatarState();
}

class _AvatarState extends State<_Avatar> {
  late final Future<Uint8List>? _bytes = widget.path == null
      ? null
      : File(widget.path!).readAsBytes();
  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) => SizedBox.square(
      dimension: 112,
      child: snapshot.hasData
          ? ClipOval(
              child: Image.memory(
                snapshot.data!,
                fit: .cover,
                semanticLabel: 'Saved account avatar',
              ),
            )
          : Tooltip(
              message: snapshot.hasError
                  ? 'Unable to read saved avatar: ${snapshot.error}'
                  : 'Account avatar',
              child: Icon(
                snapshot.hasError
                    ? Icons.broken_image_outlined
                    : Icons.person_outline_rounded,
                size: 64,
              ),
            ),
    ),
  );
}

class _AvatarCropDialog extends StatefulWidget {
  const _AvatarCropDialog({required this.path});
  final String path;
  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  ui.Image? _image;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (await File(widget.path).length() > 32 << 20) {
        throw StateError('Choose an image no larger than 32 MiB');
      }
      final buffer = await ui.ImmutableBuffer.fromFilePath(widget.path);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width > 16384 ||
              descriptor.height > 16384 ||
              descriptor.width * descriptor.height > 64000000) {
            throw StateError(
              'Choose an image up to 64 megapixels and 16,384 pixels per side',
            );
          }
          final codec = await descriptor.instantiateCodec(
            targetWidth: descriptor.width >= descriptor.height
                ? math.min(descriptor.width, 2048)
                : null,
            targetHeight: descriptor.height > descriptor.width
                ? math.min(descriptor.height, 2048)
                : null,
          );
          try {
            final image = (await codec.getNextFrame()).image;
            if (!mounted) {
              image.dispose();
              return;
            }
            setState(() => _image = image);
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Unable to load image: $error');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_image case final image?) {
      return _CropEditor(image: image, path: widget.path);
    }
    return AlertDialog(
      title: const Text('Crop avatar'),
      content: _error == null
          ? const SizedBox.square(
              dimension: 64,
              child: Center(child: CircularProgressIndicator()),
            )
          : Text(_error!),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _CropEditor extends StatefulWidget {
  const _CropEditor({required this.image, required this.path});
  final ui.Image image;
  final String path;
  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor>
    with TickerProviderStateMixin {
  late final _controller = AvatarCropController(
    imageProvider: FileImage(File(widget.path)),
    imageSize: Size(
      widget.image.width.toDouble(),
      widget.image.height.toDouble(),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final side = math.min(360.0, MediaQuery.sizeOf(context).width - 128);
    return AlertDialog(
      title: const Text('Crop avatar'),
      scrollable: true,
      content: SizedBox(
        width: side,
        child: Column(
          mainAxisSize: .min,
          children: [
            SizedBox.square(
              key: const ValueKey('avatar-crop-viewport'),
              dimension: side,
              child: _AvatarCropInput(
                controller: _controller,
                child: ClipRRect(
                  borderRadius: .circular(12),
                  // Croppy paints opacity layers; a composited child keeps the clip effective.
                  child: RepaintBoundary(
                    child: ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) => CroppableImageViewport(
                        controller: _controller,
                        gesturePadding: 0,
                        child: CroppableImageWidget(
                          controller: _controller,
                          gesturePadding: 0,
                          image: RawImage(image: widget.image, fit: .fill),
                          cropHandles: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Drag to reposition. Pinch, scroll or use the slider to zoom.',
            ),
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => Slider(
                key: const ValueKey('avatar-zoom'),
                min: 1,
                max: 8,
                value: _controller.zoom.clamp(1, 8),
                label: '${_controller.zoom.toStringAsFixed(1)}×',
                onChanged: _controller.setZoom,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('avatar-save'),
          onPressed: () => Navigator.pop(context, _controller.normalizedCrop),
          child: const Text('Save avatar'),
        ),
      ],
    );
  }
}

class _AvatarCropInput extends StatefulWidget {
  const _AvatarCropInput({required this.controller, required this.child});
  final AvatarCropController controller;
  final Widget child;
  @override
  State<_AvatarCropInput> createState() => _AvatarCropInputState();
}

class _AvatarCropInputState extends State<_AvatarCropInput> {
  double _previousScale = 1;
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (event is PointerScrollEvent) {
        GestureBinding.instance.pointerSignalResolver.register(event, (_) {
          widget.controller.setZoom(
            widget.controller.zoom * math.exp(-event.scrollDelta.dy / 240),
          );
        });
      }
    },
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (_) {
        _previousScale = 1;
        _accepted = widget.controller.onPanAndScaleStart();
      },
      onScaleUpdate: (details) {
        if (!_accepted) return;
        widget.controller.onPanAndScale(
          scaleDelta: details.scale / _previousScale,
          offsetDelta: -details.focalPointDelta,
        );
        _previousScale = details.scale;
      },
      onScaleEnd: (_) {
        if (_accepted) widget.controller.onPanAndScaleEnd();
        _accepted = false;
      },
      child: widget.child,
    ),
  );
}
