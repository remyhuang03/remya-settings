import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/appearance/application/app_preferences_controller.dart';
import 'package:remya_settings/features/appearance/data/app_preferences_file.dart';
import 'package:remya_settings/features/display/application/display_controller.dart';
import 'package:remya_settings/features/display/data/display_backend.dart';
import 'package:remya_settings/features/integration/settings_status.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';

import 'support/fake_system_appearance.dart';

Map<String, dynamic> output(
  String name, {
  int x = 0,
  bool disabled = false,
  String mirror = '',
  bool hdr = false,
  bool vrr = false,
  List<String> conflicts = const [],
  Map<String, String> overrides = const {},
}) => {
  'name': name,
  'description': '$name panel',
  'make': 'Acme',
  'model': name,
  'serial': '',
  'physical_width': 340,
  'physical_height': 220,
  'width': 1920,
  'height': 1080,
  'refresh_rate': 60.0,
  'x': x,
  'y': 0,
  'scale': 1.0,
  'transform': 0,
  'disabled': disabled,
  'vrr_active': false,
  'format': 'XRGB8888',
  'desktop_mode': '1920 × 1080 logical pixels',
  'signal_mode': '1920 × 1080 at 60.00 Hz',
  'color_space': 'Preset: srgb\nFormat: XRGB8888',
  'modes': [
    {'width': 1920, 'height': 1080, 'refresh': 144.0},
    {'width': 1920, 'height': 1080, 'refresh': 60.0},
    {'width': 1280, 'height': 720, 'refresh': 60.0},
  ],
  'scale_options': ['1', '1.25', '1.5', '2'],
  'hdr_capable': hdr,
  'wide_gamut_capable': hdr,
  'vrr_capable': vrr,
  'values': {
    'mode': '1920x1080@60.00',
    'scale': '1',
    'position': '${x}x0',
    'transform': '0',
    'mirror': mirror,
    'disabled': '$disabled',
    'cm': 'srgb',
    'bitdepth': '8',
    'vrr': '',
    'sdr_eotf': 'default',
    'icc': '',
    'reserved_area': '0 0 0 0',
    'supports_hdr': '0',
    'supports_wide_color': '0',
    'sdrbrightness': '1',
    'sdrsaturation': '1',
    'sdr_min_luminance': '0.2',
    'sdr_max_luminance': '80',
    'min_luminance': '-1',
    'max_luminance': '-1',
    'max_avg_luminance': '-1',
    ...overrides,
  },
  'saved': {'transform': '0'},
  'conflict_fields': conflicts,
};

class FakeDisplayBackend implements DisplayBackend {
  FakeDisplayBackend(this.outputs);
  List<Map<String, dynamic>> outputs;
  String? blocked;
  String? stateError;
  Object? failure;
  Map<String, dynamic>? pending;
  final writes = <(String, Map<String, dynamic>)>[];
  final resolves = <String>[];
  int reads = 0;
  Future<void>? brightnessDelay;
  final brightnessValues = <String, int>{};

  Map<String, dynamic> get state => {
    'outputs': outputs,
    'pending': pending,
    'write_blocked': blocked,
    'error': stateError,
  };

  @override
  Future<Map<String, dynamic>> read() async {
    reads++;
    return state;
  }

  @override
  Future<Map<String, dynamic>> brightness() async => {
    'outputs': [
      for (final o in outputs)
        {
          'output': o['name'],
          'percent':
              brightnessValues[o['name']] ?? (o['name'] == 'eDP-1' ? 40 : null),
          'backend': o['name'] == 'eDP-1' ? 'backlight' : null,
          'reason': o['name'] == 'eDP-1' ? '' : 'Display lacks DDC/CI',
        },
    ],
  };

  @override
  Future<Map<String, dynamic>> set(String id, String value) async {
    if (failure case final failure?) throw failure;
    if (id == displayDetectId) {
      writes.add((id, {'value': value}));
      return state;
    }
    final request = jsonDecode(value) as Map<String, dynamic>;
    writes.add((id, request));
    if (id == displayBrightnessId) {
      await brightnessDelay;
      brightnessValues[request['output'] as String] = int.parse(
        request['value'] as String,
      );
      return brightness();
    }
    if (id == displayPositionId || id == displayResolutionId) {
      final target = outputs.firstWhere((o) => o['name'] == request['output']);
      if (id == displayPositionId) {
        final parts = (request['value'] as String)
            .split('x')
            .map(int.parse)
            .toList();
        target['x'] = parts[0];
        target['y'] = parts[1];
      } else {
        (target['values'] as Map<String, dynamic>)['mode'] =
            request['value'] == 'preferred' ? 'preferred' : '1280x720@60.00';
        target['width'] = request['value'] == 'preferred' ? 1920 : 1280;
        target['height'] = request['value'] == 'preferred' ? 1080 : 720;
      }
    }
    if (id == displayOrientationId) {
      final target = outputs.firstWhere((o) => o['name'] == request['output']);
      target['transform'] = int.parse(request['value'] as String);
    }
    if (id == displayScaleId) {
      pending = {'output': request['output'], 'remaining_ms': 15000};
    }
    return state;
  }

  @override
  Future<Map<String, dynamic>> resolve(String source) async {
    if (failure case final failure?) throw failure;
    resolves.add(source);
    pending = null;
    return {'display': state};
  }
}

final catalog = SettingsCatalog.fromJson(
  jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
      as Map<String, dynamic>,
);

AppPreferencesController fakeAppPreferencesController() =>
    AppPreferencesController(
      store: AppPreferencesFile(
        File('${Directory.systemTemp.path}/remya-display-test-unused.toml'),
      ),
      systemAppearance: FakeSystemAppearance(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('snapDisplayPosition', () {
    const left = Rect.fromLTWH(0, 0, 1000, 500);
    test('edges within the threshold snap together', () {
      expect(
        snapDisplayPosition(const Rect.fromLTWH(1020, 15, 800, 400), [left]),
        const Offset(1000, 0),
      );
    });
    test('a released display never overlaps another', () {
      final place = snapDisplayPosition(
        const Rect.fromLTWH(600, 200, 800, 400),
        [left],
      );
      expect(
        const Rect.fromLTWH(0, 0, 800, 400).shift(place).overlaps(left),
        isFalse,
      );
    });
  });

  group('DisplayController', () {
    test(
      'selection survives reloads and falls back when a display leaves',
      () async {
        final backend = FakeDisplayBackend([output('A'), output('B', x: 1920)]);
        final controller = DisplayController(backend);
        await controller.reload();
        expect(controller.selected!.name, 'A');
        controller.select('B');
        await controller.reload();
        expect(controller.selected!.name, 'B');
        backend.outputs = [output('A')];
        await controller.reload();
        expect(controller.selected!.name, 'A');
      },
    );

    test(
      'changes send the confirmation window and failures stay retryable',
      () async {
        final backend = FakeDisplayBackend([output('A')]);
        final controller = DisplayController(backend);
        await controller.reload();
        backend.failure = StateError('Hyprland rejected');
        final revision = controller.revision;
        await controller.change(displayOrientationId, 'A', '1');
        expect(controller.errorMessage, contains('Hyprland rejected'));
        expect(controller.revision, isNot(revision));
        expect(backend.writes, isEmpty);

        backend.failure = null;
        await controller.retry();
        expect(controller.errorMessage, isNull);
        final (id, request) = backend.writes.single;
        expect(id, displayOrientationId);
        expect(request, {
          'output': 'A',
          'value': '1',
          'confirm_seconds': DisplayController.confirmSeconds,
        });
      },
    );

    test(
      'brightness writes serialize and keep only the newest pending value',
      () async {
        final gate = Completer<void>();
        final backend = FakeDisplayBackend([output('eDP-1')])
          ..brightnessDelay = gate.future;
        final controller = DisplayController(backend);
        await controller.reload();
        final first = controller.setBrightness('eDP-1', 45);
        controller.setBrightness('eDP-1', 60);
        final last = controller.setBrightness('eDP-1', 70);
        expect(backend.writes.length, 1);
        gate.complete();
        await Future.wait([first, last]);
        expect(backend.writes.map((w) => w.$2['value']), ['45', '70']);
        expect(controller.brightness['eDP-1']!.percent, 70);
        expect(controller.isBusy, isFalse);
      },
    );

    test('conflicts offer both resolutions through the service', () async {
      final backend = FakeDisplayBackend([
        output('A', conflicts: ['transform'], overrides: {'transform': '3'}),
      ]);
      final controller = DisplayController(backend);
      await controller.reload();
      expect(controller.hasConflict, isTrue);
      expect(controller.conflictSummary, contains('transform is 3, saved 0'));
      await controller.useSystemConfiguration();
      await controller.applySavedConfiguration();
      expect(backend.resolves, ['system', 'settings']);
    });

    test('failed resolutions keep the conflict', () async {
      final backend = FakeDisplayBackend([
        output('A', conflicts: ['transform']),
      ]);
      final controller = DisplayController(backend);
      await controller.reload();
      backend.failure = StateError('readback');
      await controller.applySavedConfiguration();
      expect(controller.hasConflict, isTrue);
      expect(controller.errorMessage, contains('readback'));
    });
  });

  group('Display page', () {
    Future<FakeDisplayBackend> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeDisplayBackend([
        output('eDP-1'),
        output('DP-3', x: 1920, hdr: true, vrr: true),
      ]);
      final controller = DisplayController(backend);
      await controller.reload();
      final navigatorKey = GlobalKey<NavigatorState>();
      final preferences = fakeAppPreferencesController();
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        DisplayScope(
          controller: controller,
          child: AppPreferencesScope(
            controller: preferences,
            child: MaterialApp(
              navigatorKey: navigatorKey,
              theme: ThemeData(useMaterial3: true),
              home: SettingsShell(
                catalog: catalog,
                navigation: ValueNotifier('display'),
                status: SettingsStatus(
                  preferences: preferences,
                  display: controller,
                  navigatorKey: navigatorKey,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('risky changes ask to keep or revert with a countdown', (
      tester,
    ) async {
      final backend = await pump(tester);
      final controller = DisplayScope.maybeOf(
        tester.element(find.byKey(const ValueKey('display-arrangement'))),
      )!;
      await controller.change(displayScaleId, 'eDP-1', '1.5');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(find.text('Keep these display settings?'), findsOneWidget);
      expect(find.textContaining('15 seconds'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('display-confirm-revert')));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(backend.resolves, ['revert']);
      expect(find.text('Keep these display settings?'), findsNothing);

      await controller.change(displayScaleId, 'eDP-1', '1.5');
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('display-confirm-keep')));
      await tester.pump();
      await tester.pumpAndSettle(const Duration(milliseconds: 300));
      expect(backend.resolves, ['revert', 'keep']);
    });
  });
}
