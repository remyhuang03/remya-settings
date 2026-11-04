import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/camera/application/camera_controller.dart';
import 'package:remya_settings/features/camera/data/camera_preview.dart';
import 'package:remya_settings/features/camera/presentation/camera_page.dart';

class Preview implements CameraPreview {
  int starts = 0, stops = 0;
  Completer<ui.Image> pending = Completer();
  @override
  Future<void> start(String camera, int serial) async {
    starts++;
  }

  @override
  Future<ui.Image> frame() => pending.future;
  @override
  Future<void> stop() async {
    stops++;
  }
}

Map<String, dynamic> snapshot() => {
  'available': true,
  'devices': [
    {
      'name': 'camera',
      'serial': 1,
      'description': 'Camera',
      'controls': {
        'brightness': {
          'value': 2,
          'min': 0,
          'max': 10,
          'step': 1,
          'default': 5,
          'writable': true,
        },
      },
    },
  ],
  'saved': {
    'camera': {'brightness': 2},
  },
  'conflicts': <String>[],
  'error': null,
};
void main() {
  CameraController controller(
    Map<String, dynamic> state, {
    List<Object>? requests,
  }) => CameraController(
    read: () async => state,
    write: (field, name, serial, {value}) async {
      requests?.add([field, name, serial, value]);
      return state;
    },
    resolve: (camera, source) async {
      requests?.add([camera, source]);
      return state;
    },
  );
  test('controller forwards device identity and both resolutions', () async {
    final state = snapshot(), requests = <Object>[];
    final c = controller(state, requests: requests);
    addTearDown(c.dispose);
    await c.reload();
    await c.set(c.devices.first, 'brightness', value: 3);
    await c.reconcile(c.devices.first, 'system');
    await c.reconcile(c.devices.first, 'settings');
    expect(requests, [
      ['brightness', 'camera', 1, 3.0],
      ['camera', 'system'],
      ['camera', 'settings'],
    ]);
  });
  testWidgets('released slider retains its value while readback is pending', (
    tester,
  ) async {
    final state = snapshot();
    final pending = Completer<Map<String, dynamic>>();
    final c = CameraController(
      read: () async => state,
      write: (_, _, _, {value}) => pending.future,
      resolve: (_, _) async => state,
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CameraPage(controller: c, preview: Preview()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged!(6);
    await tester.pump();
    tester.widget<Slider>(find.byType(Slider)).onChangeEnd!(6);
    await tester.pump();
    expect(c.busy, isTrue);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 6);
    (state['devices'] as List).first['controls']['brightness']['value'] = 6;
    pending.complete(state);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 6);
    expect(c.busy, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('parameters sit beside preview and stack on narrow windows', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final c = controller(snapshot());
    addTearDown(c.dispose);
    final preview = Preview();
    for (final width in [1200.0, 500.0]) {
      tester.view.physicalSize = Size(width, 1200);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CameraPage(
                key: ValueKey(width),
                controller: c,
                preview: preview,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Contrast'), findsNothing);
      expect(find.text('Brightness'), findsOneWidget);
      expect(preview.starts, 0);
      final viewer = tester.getRect(find.byType(AspectRatio));
      final control = tester.getRect(find.text('Brightness'));
      if (width == 1200) {
        expect(control.left, greaterThan(viewer.right));
      } else {
        expect(control.top, greaterThan(viewer.bottom));
      }
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'preview is opt-in and stops on page removal; late frames are ignored',
    (tester) async {
      final c = controller(snapshot());
      addTearDown(c.dispose);
      final preview = Preview();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CameraPage(controller: c, preview: preview),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(preview.starts, 0);
      await tester.tap(find.text('Start preview'));
      await tester.pump();
      expect(preview.starts, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(preview.stops, greaterThan(0));
      preview.pending.completeError(StateError('Preview disconnected'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
