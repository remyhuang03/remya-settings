import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../../../src/rust/camera_bridge/api.dart' as api;
import '../../../src/rust/camera_bridge/frb_generated.dart';

abstract interface class CameraPreview {
  Future<void> start(String camera, int serial);
  Future<ui.Image> frame();
  Future<void> stop();
}

class RustCameraPreview implements CameraPreview {
  static Future<void>? _initializing;
  BigInt? _id;
  int _generation = 0;
  @override
  Future<void> start(String camera, int serial) async {
    final generation = ++_generation;
    await (_initializing ??= CameraRustLib.init(
      externalLibrary: ExternalLibrary.open(
        '${File(Platform.resolvedExecutable).parent.path}/lib/libremya_settings_camera.so',
      ),
    ));
    final id = await api.startPreview(
      camera: camera,
      serial: BigInt.from(serial),
    );
    if (generation != _generation) {
      await api.stopPreview(id: id);
      return;
    }
    _id = id;
  }

  @override
  Future<ui.Image> frame() async {
    final id = _id;
    if (id == null) throw StateError('Preview stopped');
    final frame = await api.nextPreviewFrame(id: id);
    final ready = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      frame.rgba,
      frame.width,
      frame.height,
      ui.PixelFormat.rgba8888,
      ready.complete,
    );
    return ready.future;
  }

  @override
  Future<void> stop() async {
    _generation++;
    final id = _id;
    _id = null;
    if (id != null) await api.stopPreview(id: id);
  }
}
