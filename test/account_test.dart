import 'support/catalog.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:croppy/croppy.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:remya_settings/features/account/presentation/avatar_crop_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/account/application/account_controller.dart';
import 'package:remya_settings/features/account/presentation/account_information_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_client/settings_contract.dart';

Map<String, dynamic> _state() => {
  'username': 'test-user',
  'avatar_path': null,
  'avatar_revision': null,
  'error': null,
};

void main() {
  test(
    'failed avatar saves keep the last valid profile and show the failure',
    () async {
      final controller = AccountController(
        read: () async => _state(),
        save: (_, _) async => throw StateError('read-only destination'),
      );
      addTearDown(controller.dispose);
      await controller.reload();
      final previous = controller.value;
      await controller.saveAvatar('/tmp/avatar.png', {
        'left': 0,
        'top': 0,
        'right': 1,
        'bottom': 1,
      });
      expect(controller.value, same(previous));
      expect(controller.errorMessage, contains('read-only destination'));
      expect(controller.isBusy, isFalse);
    },
  );

  test(
    'crop zoom preserves the center, clamps limits and retains a square',
    () {
      final controller = AvatarCropController(
        imageProvider: const AssetImage('unused'),
        imageSize: const Size(1200, 800),
      );
      addTearDown(controller.dispose);
      controller.viewportSize = const Size(360, 360);
      final center = controller.data.cropRect.center;
      controller.setZoom(3);
      expect(controller.zoom, closeTo(3, .001));
      expect(controller.data.cropRect.center, center);
      controller.setZoom(99);
      expect(controller.zoom, closeTo(8, .001));
      controller.onPanAndScaleStart();
      controller.onPanAndScale(
        scaleDelta: 1,
        offsetDelta: const Offset(10000, -10000),
      );
      controller.onPanAndScaleEnd();
      final crop = controller.normalizedCrop;
      expect(crop.values.every((value) => value >= 0 && value <= 1), isTrue);
      expect(
        controller.data.cropRect.width,
        closeTo(controller.data.cropRect.height, .001),
      );
      controller.setZoom(.01);
      expect(controller.zoom, closeTo(1, .001));
    },
  );

  testWidgets(
    'identity is read-only and only an accepted crop saves the avatar',
    (tester) async {
      final directory = Directory.systemTemp.createTempSync(
        'remya-avatar-test-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final source = File('${directory.path}/source.png')
        ..writeAsBytesSync(
          base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAGUlEQVR4nGP8z8DAwMDAyPCfgYGBiQEJAAAqNwIDlBYW1QAAAABJRU5ErkJggg==',
          ),
        );
      final writes = <(String, Map<String, double>)>[];
      final controller = AccountController(
        read: () async => _state(),
        save: (path, crop) async {
          writes.add((path, crop));
          return _state();
        },
      );
      addTearDown(controller.dispose);
      final catalog = SettingsCatalog.fromJson(readCatalog());
      final capture = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: AccountInformationPage(
                  page: catalog.page('your-info'),
                  controller: controller,
                  pickImage: () async => source.path,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('test-user'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      final choose = find.byKey(const ValueKey(accountAvatarSettingId));
      await tester.tap(choose);
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, isEmpty);
      await tester.tap(choose);
      await tester.pump();
      for (
        var i = 0;
        i < 30 &&
            find
                .byKey(const ValueKey('avatar-crop-viewport'))
                .evaluate()
                .isEmpty;
        i++
      ) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('avatar-crop-viewport')),
        findsOneWidget,
      );
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('avatar-zoom')),
      );
      slider.onChanged!(2);
      await tester.pump();
      final cropViewport = find.byKey(const ValueKey('avatar-crop-viewport'));
      final cropController =
          tester
                  .widget<CroppableImageWidget>(
                    find.byType(CroppableImageWidget),
                  )
                  .controller
              as AvatarCropController;
      expect(cropController.zoom, closeTo(2, .001));
      final cropBounds = tester.getRect(cropViewport).inflate(2);
      final frame = await tester.runAsync(() async {
        final image =
            await (capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          return (image.width, image.height, bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      expect(
        _coloredPixelsOutside(frame!.$1, frame.$2, frame.$3, cropBounds),
        0,
        reason: 'Composited crop image layers must stay inside the visible crop square.',
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(cropViewport),
          scrollDelta: const Offset(0, -100),
        ),
      );
      await tester.pumpAndSettle();
      expect(cropController.zoom, greaterThan(2));
      expect(
        tester.widget<Slider>(find.byKey(const ValueKey('avatar-zoom'))).value,
        closeTo(cropController.zoom, .001),
      );
      final zoomAfterWheel = cropController.zoom;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(cropViewport),
          scrollDelta: const Offset(0, 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(cropController.zoom, lessThan(zoomAfterWheel));
      expect(cropController.zoom, closeTo(2, .001));
      final center = tester.getCenter(cropViewport);
      final first = await tester.startGesture(
        center + const Offset(-40, 0),
        pointer: 11,
      );
      final second = await tester.startGesture(
        center + const Offset(40, 0),
        pointer: 12,
      );
      await first.moveTo(center + const Offset(-80, 0));
      await second.moveTo(center + const Offset(80, 0));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(cropController.zoom, greaterThan(2));
      expect(
        tester.widget<Slider>(find.byKey(const ValueKey('avatar-zoom'))).value,
        closeTo(cropController.zoom, .001),
      );
      final zoomAfterPinch = cropController.zoom;
      final beforeDrag = cropController.data.cropRect;
      await tester.drag(cropViewport, const Offset(-40, 0));
      await tester.pumpAndSettle();
      expect(cropController.data.cropRect.left, greaterThan(beforeDrag.left));
      expect(cropController.zoom, closeTo(zoomAfterPinch, .001));
      cropController.setZoom(2);
      await tester.pumpAndSettle();
      expect(
        tester.widget<Slider>(find.byKey(const ValueKey('avatar-zoom'))).value,
        closeTo(2, .001),
      );
      await tester.tap(find.byKey(const ValueKey('avatar-save')));
      await tester.pumpAndSettle();
      expect(writes.single.$1, source.path);
      final crop = writes.single.$2;
      expect(crop.values.every((n) => n >= 0 && n <= 1), isTrue);
      expect(crop['right']! - crop['left']!, closeTo(.25, .001));
      expect(crop['bottom']! - crop['top']!, closeTo(.5, .001));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

int _coloredPixelsOutside(int width, int height, Uint8List rgba, Rect bounds) {
  var count = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (bounds.contains(Offset(x.toDouble(), y.toDouble()))) continue;
      final offset = (y * width + x) * 4;
      final red = rgba[offset];
      final green = rgba[offset + 1];
      final blue = rgba[offset + 2];
      if ((red > 15 && green < 3 && blue < 3) ||
          (blue > 15 && red < 3 && green < 3)) {
        count++;
      }
    }
  }
  return count;
}
