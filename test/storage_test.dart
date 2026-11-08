import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/storage/application/storage_controller.dart';
import 'package:remya_settings/features/storage/presentation/storage_page.dart';
import 'package:remya_settings/features/storage/presentation/cleanup_page.dart';
import 'package:remya_settings/features/storage/presentation/storage_widgets.dart';

Map<String, dynamic> storageState({bool scanning = false, int free = 20}) => {
  'busy': false,
  'error': null,
  'reclaimable_bytes': 900,
  'usage': {
    'scanning': scanning,
    'progress': {'files': 42, 'bytes': 100},
    'scanned_at': 1700000000,
    'skipped': 0,
    'volume': {
      'mount_point': '/',
      'device': '/dev/test',
      'total': 100 * 1024 * 1024,
      'used': 80 * 1024 * 1024,
      'free': free * 1024 * 1024,
    },
    'categories': [
      {
        'id': 'documents',
        'label': 'Documents',
        'bytes': 30 * 1024 * 1024,
        'path': '/test/Documents',
      },
      {
        'id': 'system',
        'label': 'System and other files',
        'bytes': 50 * 1024 * 1024,
        'path': null,
      },
    ],
  },
  'drives': [
    {
      'id': '/drive',
      'model': 'Test SSD',
      'vendor': 'Test',
      'size': 100,
      'connection': 'nvme',
      'rotational': false,
      'removable': false,
      'media_removable': false,
      'can_power_off': true,
      'ejectable': true,
      'volumes': [
        {
          'id': '/volume',
          'device': '/dev/test',
          'label': 'Root',
          'fs_type': 'ext4',
          'size': 80,
          'offset': 0,
          'number': 1,
          'mount_points': ['/'],
          'usage': {'total': 80, 'used': 60, 'free': 20},
          'system': true,
          'can_mount': false,
          'can_unmount': false,
          'can_rename': false,
        },
      ],
    },
  ],
};
Map<String, dynamic> cleanupState({bool automatic = false}) => {
  'busy': false,
  'writable': true,
  'error': null,
  'reclaimable_bytes': 900,
  'trash': {'items': 2, 'bytes': 100, 'broken': 0},
  'cache': {
    'bytes': 200,
    'folders': [
      {'name': 'test-app', 'bytes': 200},
    ],
  },
  'package_cache': {
    'bytes': 1000,
    'candidates': {'1': 500, '2': 300, '3': 100},
    'uninstalled_bytes': 50,
    'missing_tool': null,
  },
  'orphans': {
    'bytes': 300,
    'packages': [
      {'name': 'unused', 'version': '1.0-1', 'bytes': 300},
    ],
  },
  'large_files': {
    'files': [
      {
        'path': '/test/Downloads/large.iso',
        'bytes': 100000000,
        'modified': 1700000000,
      },
    ],
  },
  'automatic': {
    'enabled': automatic,
    'frequency': 'low-space',
    'trash_days': 30,
    'cache_days': 30,
    'downloads_days': 0,
  },
  'last_run': null,
};
StorageController controller({
  Map<String, dynamic>? storage,
  Map<String, dynamic>? cleanup,
  List<(String, String)>? writes,
}) {
  final s = storage ?? storageState(), c = cleanup ?? cleanupState();
  return StorageController(
    readStorage: () async => s,
    readCleanup: () async => c,
    write: (id, text) async {
      writes?.add((id, text));
      if (id == 'cleanup.auto') {
        (c['automatic'] as Map)['enabled'] = jsonDecode(text);
      }
      return id.startsWith('storage.') ? s : c;
    },
    formatDate: (_) async => '11/14/2023',
  );
}

Future<void> page(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1100, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: true),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const .all(20), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  test('categorical palette is distinct, brightness-aware and harmonized', () {
    for (final brightness in Brightness.values) {
      final scheme = ColorScheme.fromSeed(
        seedColor: Colors.purple,
        brightness: brightness,
      );
      final palette = storageColors(scheme);
      expect(palette.toSet().length, palette.length);
      expect(palette.length, greaterThanOrEqualTo(9));
      expect(
        palette,
        isNot(
          storageColors(
            ColorScheme.fromSeed(
              seedColor: Colors.blue,
              brightness: brightness,
            ),
          ),
        ),
      );
      for (final color in palette) {
        expect(
          color.computeLuminance(),
          brightness == Brightness.dark ? greaterThan(0.3) : lessThan(0.2),
        );
      }
    }
  });

  testWidgets('usage hides tiny categories and stacks legend on narrow pages', (
    tester,
  ) async {
    final state = storageState();
    (state['usage']['categories'] as List).add({
      'id': 'tiny',
      'label': 'Tiny category',
      'bytes': 1024,
      'path': null,
    });
    state['usage']['volume']['mount_point'] = '/home';
    final c = controller(storage: state);
    addTearDown(c.dispose);
    await page(tester, StoragePage(controller: c, onPage: (_) {}));
    await tester.pumpAndSettle();
    expect(find.text('/home'), findsOneWidget);
    expect(find.text('/dev/test mounted at /home'), findsOneWidget);
    expect(find.text('Tiny category'), findsNothing);
    tester.view.physicalSize = const Size(580, 2200);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Documents')).dy,
      greaterThan(tester.getTopLeft(find.text('System and other files')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cleanup hides zero-byte legend entries and shows recommendation errors',
    (tester) async {
      final state = cleanupState();
      state['trash'] = {'error': 'Cannot list Trash'};
      state['cache'] = {'bytes': 0, 'folders': <Map>[]};
      state['orphans'] = {'bytes': 0, 'packages': <Map>[]};
      final c = controller(cleanup: state);
      addTearDown(c.dispose);
      await page(tester, CleanupPage(controller: c));
      await tester.pumpAndSettle();
      final legends = tester.widgetList<StorageLegend>(
        find.byType(StorageLegend),
      );
      expect(legends.map((e) => e.label), ['Package cache']);
      final trashRow = find.byKey(const ValueKey('cleanup-trash'));
      expect(
        find.descendant(of: trashRow, matching: find.text('Cannot list Trash')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: trashRow,
          matching: find.byIcon(Icons.error_outline_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: trashRow, matching: find.text('0 B')),
        findsNothing,
      );
      expect(
        find.descendant(of: trashRow, matching: find.byType(Checkbox)),
        findsNothing,
      );
    },
  );

  testWidgets(
    'storage shows real usage legend and keyboard-selectable partitions; protects system volume actions',
    (tester) async {
      final c = controller();
      addTearDown(c.dispose);
      final navigation = <String>[];
      await page(tester, StoragePage(controller: c, onPage: navigation.add));
      await tester.pumpAndSettle();
      expect(find.text('80.0 MiB  used', findRichText: true), findsOneWidget);
      expect(find.text('20.0 MiB free'), findsOneWidget);
      expect(find.text('of 100.0 MiB'), findsOneWidget);
      expect(find.text('System drive'), findsOneWidget);
      expect(find.text('/dev/test mounted at /'), findsOneWidget);
      expect(find.text('Documents'), findsOneWidget);
      final legends = tester
          .widgetList<StorageLegend>(find.byType(StorageLegend))
          .toList();
      expect(legends.map((e) => e.label), [
        'System and other files',
        'Documents',
        'Free space',
      ]);
      expect(
        tester.getTopLeft(find.text('Documents')).dy,
        tester.getTopLeft(find.text('System and other files')).dy,
      );
      expect(find.byKey(const ValueKey('partition-map')), findsOneWidget);
      expect(find.text('Unmount'), findsNothing);
      expect(find.text('Rename'), findsNothing);
      expect(find.byTooltip('Drive actions'), findsNothing);
      await tester.tap(find.text('System and other files'));
      expect(navigation, ['installed']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('storage shows scanning progress and almost full warning', (
    tester,
  ) async {
    final c = controller(storage: storageState(scanning: true, free: 5));
    addTearDown(c.dispose);
    await page(tester, StoragePage(controller: c, onPage: (_) {}));
    expect(find.text('Scanning 42 files'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Scan again'), findsNothing);
    expect(find.text('Storage is almost full'), findsOneWidget);
  });
  testWidgets(
    'cleanup selection totals and confirmation distinguish deletion from trash',
    (tester) async {
      final writes = <(String, String)>[];
      final c = controller(writes: writes);
      addTearDown(c.dispose);
      await page(tester, CleanupPage(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox).at(0));
      await tester.pump();
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();
      expect(find.text('300 B selected'), findsOneWidget);
      final clean = find.byKey(const ValueKey('cleanup-run'));
      await tester.ensureVisible(clean);
      await tester.tap(clean);
      await tester.pumpAndSettle();
      expect(find.text('Clean up 300 B?'), findsOneWidget);
      expect(find.text('Permanently delete'), findsOneWidget);
      expect(find.text('Trash: 2 items'), findsOneWidget);
      expect(find.text('Cache folder: test-app (200 B)'), findsOneWidget);
      expect(find.text('Move to Trash'), findsNothing);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(Checkbox).at(4));
      await tester.tap(find.byType(Checkbox).at(4));
      await tester.pump();
      await tester.ensureVisible(clean);
      await tester.tap(clean);
      await tester.pumpAndSettle();
      expect(find.text('Move to Trash'), findsOneWidget);
      expect(find.text('/test/Downloads/large.iso'), findsOneWidget);
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'automatic choices hide when off and update through the controller',
    (tester) async {
      final writes = <(String, String)>[];
      final c = controller(writes: writes);
      addTearDown(c.dispose);
      await page(tester, CleanupPage(controller: c));
      await tester.pumpAndSettle();
      expect(find.text('Run'), findsNothing);
      expect(find.text('Delete unused cached files'), findsNothing);
      final toggle = find.descendant(
        of: find.byKey(const ValueKey('cleanup.auto')),
        matching: find.byType(Switch),
      );
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Delete unused cached files'), findsOneWidget);
      expect(writes.single, ('cleanup.auto', 'true'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('runtime missing tool is visible and cannot be selected', (
    tester,
  ) async {
    final state = cleanupState();
    (state['package_cache'] as Map)['missing_tool'] = 'Install pacman-contrib';
    final c = controller(cleanup: state);
    addTearDown(c.dispose);
    await page(tester, CleanupPage(controller: c));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey('cleanup-package-cache'));
    expect(
      find.descendant(of: row, matching: find.text('Install pacman-contrib')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(Checkbox)),
      findsNothing,
    );
  });
}
