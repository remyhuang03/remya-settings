import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
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
  'color_space': 'srgb · XRGB8888',
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
          'percent': o['name'] == 'eDP-1' ? 40 : null,
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
    if (id == displayBrightnessId) return brightness();
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

final mainScroll = find
    .descendant(
      of: find.byKey(const ValueKey('settings-main-content')),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('catalog', () {
    test(
      'advanced display options live in a collapsed Display section',
      () async {
        final page = catalog.page('display');
        final advanced = page.sections.singleWhere(
          (s) => s.title == 'Advanced',
        );
        expect(advanced.collapsed, isTrue);
        expect(advanced.controls.map((c) => c.id), contains(displayVrrId));
        expect(
          page.sections
              .firstWhere((s) => s.title == 'Scale and layout')
              .controls
              .map((c) => c.id),
          contains(displayRefreshId),
        );
        expect(catalog.page('advanced-display').id, 'display');
        expect(catalog.page('hypr-monitor-fields').id, 'display');
        expect(page.windowsUris, contains('ms-settings:display-advanced'));
        for (final id in displaySettingIds) {
          final control = page.controls.singleWhere((c) => c.id == id);
          expect(
            control.availability,
            SettingAvailability.available,
            reason: id,
          );
        }
        expect(
          catalog.inCategory('system').map((p) => p.id),
          isNot(contains('advanced-display')),
        );
      },
    );
  });

  group('snapDisplayPosition', () {
    const left = Rect.fromLTWH(0, 0, 1000, 500);
    test('edges within the threshold snap together', () {
      expect(
        snapDisplayPosition(const Rect.fromLTWH(1020, 15, 800, 400), [left]),
        const Offset(1000, 0),
      );
    });
    test('far positions are kept and rounded', () {
      expect(
        snapDisplayPosition(const Rect.fromLTWH(2000.4, 900.6, 800, 400), [
          left,
        ]),
        const Offset(2000, 901),
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

    test('a background reload never recreates controls', () async {
      final controller = DisplayController(FakeDisplayBackend([output('A')]));
      await controller.reload();
      final revision = controller.revision;
      await controller.reload();
      expect(controller.revision, revision);
    });

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

    test('detection errors reported by the service stay visible', () async {
      final backend = FakeDisplayBackend([])
        ..stateError = 'Hyprland is not running';
      final controller = DisplayController(backend);
      await controller.reload();
      expect(controller.errorMessage, 'Hyprland is not running');
      expect(controller.selected, isNull);
    });

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
    Future<FakeDisplayBackend> pump(
      WidgetTester tester, {
      List<Map<String, dynamic>>? outputs,
      void Function(FakeDisplayBackend)? configure,
      String page = 'display',
      ValueNotifier<String?>? navigation,
    }) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeDisplayBackend(
        outputs ??
            [output('eDP-1'), output('DP-3', x: 1920, hdr: true, vrr: true)],
      );
      configure?.call(backend);
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
                navigation: navigation ?? ValueNotifier(page),
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

    Future<void> scrollTo(WidgetTester tester, Finder finder) async {
      await tester.scrollUntilVisible(finder, 200, scrollable: mainScroll);
      await tester.pumpAndSettle();
    }

    testWidgets('shows real displays and hides advanced options by default', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byKey(const ValueKey('display-arrangement')), findsOneWidget);
      expect(find.byKey(const ValueKey('display-tile-eDP-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('display-tile-DP-3')), findsOneWidget);
      expect(find.text('Display arrangement · Preview'), findsNothing);
      expect(find.text('Advanced'), findsOneWidget);
      expect(find.text('Variable refresh rate'), findsNothing);
      expect(find.text('Advanced display'), findsNothing);
      expect(
        find.byKey(const ValueKey('nav-page-advanced-display')),
        findsNothing,
      );
    });

    testWidgets('expands Advanced on tap and for the retired page ID', (
      tester,
    ) async {
      await pump(tester);
      await scrollTo(tester, find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(
        find.text('Variable refresh rate', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a deep link to Advanced display opens the section', (
      tester,
    ) async {
      await pump(tester, page: 'advanced-display');
      // Read-only rows keep their information in the left column.
      expect(
        tester.getTopLeft(find.text('Desktop mode', skipOffstage: false)).dx,
        tester.getTopLeft(find.text('Bit depth', skipOffstage: false)).dx,
      );
      expect(
        find.text('Variable refresh rate', skipOffstage: false),
        findsOneWidget,
      );
    });

    testWidgets('a deep link expands Advanced on an already open page', (
      tester,
    ) async {
      final navigation = ValueNotifier<String?>('display');
      await pump(tester, navigation: navigation);
      expect(find.text('Variable refresh rate'), findsNothing);
      navigation.value = 'advanced-display';
      await tester.pumpAndSettle();
      expect(
        find.text('Variable refresh rate', skipOffstage: false),
        findsOneWidget,
      );
    });

    for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
      testWidgets('dragging a display saves its snapped position with $kind', (
        tester,
      ) async {
        final backend = await pump(tester);
        final tile = find.byKey(const ValueKey('display-tile-DP-3'));
        await scrollTo(tester, tile);
        final scrolled = tester
            .state<ScrollableState>(mainScroll)
            .position
            .pixels;
        await tester.drag(tile, const Offset(0, 30), kind: kind);
        await tester.pumpAndSettle();
        final (id, request) = backend.writes.last;
        expect(id, displayPositionId);
        expect(request['output'], 'DP-3');
        final [x, y] = (request['value'] as String)
            .split('x')
            .map(int.parse)
            .toList();
        expect(x, 1920, reason: 'stays attached to its neighbour');
        expect(y, greaterThan(0));
        expect(
          tester.state<ScrollableState>(mainScroll).position.pixels,
          scrolled,
          reason: 'the drag must not scroll the page',
        );
      });
    }

    testWidgets('tapping a display selects it without moving it', (
      tester,
    ) async {
      final backend = await pump(tester);
      final tile = find.byKey(const ValueKey('display-tile-DP-3'));
      await scrollTo(tester, tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(backend.writes, isEmpty);
      final controller = DisplayScope.maybeOf(tester.element(tile))!;
      expect(controller.selected!.name, 'DP-3');
    });

    testWidgets('selecting a display updates capability gated controls', (
      tester,
    ) async {
      await pump(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('display-control-$displayHdrId')),
        200,
        scrollable: mainScroll,
      );
      Switch hdr() => tester.widget<Switch>(
        find.byKey(const ValueKey('display-control-$displayHdrId')),
      );
      expect(hdr().onChanged, isNull);
      expect(
        find.text('This display does not report HDR support.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('display-tile-DP-3')),
        -200,
        scrollable: mainScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('display-tile-DP-3')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('display-control-$displayHdrId')),
        200,
        scrollable: mainScroll,
      );
      expect(hdr().onChanged, isNotNull);
      expect(
        find.text('This display does not report HDR support.'),
        findsNothing,
      );
    });

    testWidgets('brightness shows its value or why it is unavailable', (
      tester,
    ) async {
      await pump(tester);
      final readout = find.byKey(
        const ValueKey('display-readout-$displayBrightnessId'),
      );
      await tester.scrollUntilVisible(readout, 200, scrollable: mainScroll);
      expect(tester.widget<Text>(readout).data, '40%');
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('display-tile-DP-3')),
        -200,
        scrollable: mainScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('display-tile-DP-3')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Display lacks DDC/CI'),
        200,
        scrollable: mainScroll,
      );
      expect(find.text('Display lacks DDC/CI'), findsOneWidget);
      expect(
        tester
            .widget<Slider>(
              find.byKey(
                const ValueKey('display-control-$displayBrightnessId'),
              ),
            )
            .onChanged,
        isNull,
      );
    });

    testWidgets('a blocked rule file disables writes and explains why', (
      tester,
    ) async {
      await pump(
        tester,
        configure: (backend) => backend.blocked = 'Cannot edit monitors.lua',
      );
      expect(find.text('Cannot edit monitors.lua'), findsOneWidget);
      final orientation = find.byKey(
        const ValueKey('display-control-$displayOrientationId'),
      );
      await tester.scrollUntilVisible(orientation, 200, scrollable: mainScroll);
      final field = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: orientation,
          matching: find.byType(DropdownButton<String>),
        ),
      );
      expect(field.onChanged, isNull);
    });

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

    testWidgets('a conflict warning offers both choices', (tester) async {
      final backend = await pump(
        tester,
        outputs: [
          output('A', conflicts: ['transform'], overrides: {'transform': '3'}),
        ],
      );
      expect(find.text('Configuration differs'), findsOneWidget);
      await tester.tap(find.text('Use system configuration'));
      await tester.pumpAndSettle();
      expect(backend.resolves, ['system']);
    });

    testWidgets('disabled displays are listed and can be selected', (
      tester,
    ) async {
      await pump(tester, outputs: [output('A'), output('B', disabled: true)]);
      expect(find.byKey(const ValueKey('display-tile-B')), findsNothing);
      await scrollTo(tester, find.byKey(const ValueKey('display-idle-B')));
      await tester.tap(find.byKey(const ValueKey('display-idle-B')));
      await tester.pumpAndSettle();
      await scrollTo(
        tester,
        find.byKey(const ValueKey('display-hint-$displayScaleId')),
      );
      expect(find.text('This display is not in use.'), findsWidgets);
    });

    testWidgets(
      'the page opens related previews and stays usable when narrow',
      (tester) async {
        await pump(tester);
        final night = find.byKey(const ValueKey('open-page-display.e32be03e'));
        await scrollTo(tester, night);
        await tester.tap(night);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('night-light.e32be03e')),
          findsOneWidget,
        );

        tester.view.physicalSize = const Size(420, 800);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  });
}
