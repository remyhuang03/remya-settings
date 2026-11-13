import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_settings/features/settings/presentation/settings_shell.dart';

const summary = {'id': 'display', 'title': 'Display', 'category': 'system'};
const detail = {
  ...summary,
  'description': 'Screens',
  'preview': 'display',
  'availability': 'available',
  'reason': 'Verified integration',
  'windowsUris': <String>[],
  'children': <String>[],
  'sections': <Object>[],
};

class CatalogService extends SettingsClient {
  final events = StreamController<SettingsChange>.broadcast(sync: true);
  final calls = <(String, List<String>)>[];
  Completer<void>? gate;
  Object? failure;
  Map<String, dynamic> page = detail;
  @override
  Stream<SettingsChange> get changes => events.stream;
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    List<String> arguments = const [],
  ]) async {
    calls.add((method, arguments));
    if (arguments.firstOrNull == 'catalog') {
      return {
        'version': 1,
        'sources': <Object>[],
        'categories': [
          {
            'id': 'system',
            'title': 'System',
            'description': 'Device',
            'icon': 'computer',
          },
        ],
        'pages': [summary],
      };
    }
    if (arguments.firstOrNull == 'page:display') {
      await gate?.future;
      if (failure != null) throw failure!;
      return page;
    }
    if (method == 'Search') {
      return {
        'pages': [
          summary,
          {
            'id': 'remya-bar.height',
            'title': 'Bar height',
            'app': 'remya-bar',
            'page': 'layout',
          },
        ],
      };
    }
    if (method == 'List') {
      return {
        'api_version': 1,
        'next_cursor': null,
        'controls': <Object>[],
        'apps': [
          {
            'id': 'remya-bar',
            'app': 'top.remya.bar',
            'title': 'Remya Bar',
            'icon': 'top.remya.bar',
            'pages': [
              {'id': 'layout', 'title': 'Layout', 'keywords': <String>[]},
            ],
          },
          {
            'id': 'broken',
            'app': null,
            'title': 7,
            'icon': null,
            'pages': <Object>[],
            'error': 'missing field `config`',
          },
        ],
      };
    }
    if (method == 'Manage' && failure != null) throw failure!;
    return {};
  }
}

void main() {
  late CatalogService service;
  late SettingsCatalog catalog;
  setUp(() async {
    service = CatalogService();
    catalog = await SettingsCatalog.load(client: service);
  });
  tearDown(() async {
    catalog.dispose();
    await service.events.close();
    await service.close();
  });

  test(
    'loads summaries first, caches pages and manages once per session',
    () async {
      expect(service.calls.single.$1, 'Get');
      expect(service.calls.single.$2, ['catalog']);
      expect(catalog.page('display').sections, isEmpty);
      service.gate = Completer<void>();
      final pending = catalog.openPage('display');
      expect(catalog.loadingPages, {'display'});
      expect(identical(pending, catalog.openPage('display')), isTrue);
      service.gate!.complete();
      await pending;
      expect(catalog.page('display').description, 'Screens');
      expect(catalog.loadingPages, isEmpty);
      await catalog.openPage('display');
      expect(
        service.calls.where((c) => c.$2.firstOrNull == 'page:display'),
        hasLength(1),
      );
      expect(service.calls.where((c) => c.$1 == 'Manage').single.$2, [
        'display',
      ]);
      await catalog.reload();
      expect(
        service.calls.where((c) => c.$2.firstOrNull == 'page:display'),
        hasLength(2),
      );
      expect(service.calls.where((c) => c.$1 == 'Manage'), hasLength(1));
    },
  );

  test('failed refresh and malformed details retain last valid page, retry succeeds', () async {
    await catalog.openPage('display');
    final valid = catalog.page('display');
    service.failure = StateError('Core unavailable');
    await catalog.refreshPages();
    expect(catalog.page('display'), same(valid));
    expect(catalog.pageErrors['display'], isStateError);
    service.failure = null;
    service.page = {...detail, 'id': 'wrong'};
    await catalog.refreshPages();
    expect(catalog.page('display'), same(valid));
    expect(catalog.pageErrors['display'], isFormatException);
    service.page = {...detail, 'description': 'Fresh screens'};
    await catalog.openPage('display');
    expect(catalog.pageErrors, isEmpty);
    expect(catalog.page('display').description, 'Fresh screens');
  });

  test(
    'Changed invalidates opened details, Search includes app handoff data',
    () async {
      await catalog.openPage('display');
      service.page = {...detail, 'description': 'Changed screens'};
      final changed = Completer<void>();
      catalog.addListener(() {
        if (!changed.isCompleted &&
            catalog.page('display').description == 'Changed screens') {
          changed.complete();
        }
      });
      service.events.add((topic: 'display', value: {}));
      await changed.future;
      expect(catalog.search('screens'), isEmpty);
      expect(catalog.searching, isTrue);
      final searched = Completer<void>();
      catalog.addListener(() {
        if (!catalog.searching && !searched.isCompleted) searched.complete();
      });
      await searched.future;
      expect(catalog.search('screens').single.id, 'display');
      expect(catalog.searchResults, hasLength(2));
    },
  );

  test(
    'apps include rejected registrations and search routes to OpenApp',
    () async {
      await catalog.loadApps();
      final [bar, broken] = catalog.apps!;
      expect(bar.title, 'Remya Bar');
      expect(bar.pages.single, (id: 'layout', title: 'Layout'));
      expect(bar.error, isNull);
      expect(broken.title, isNull);
      expect(broken.error, contains('config'));
      expect(catalog.appTitle('broken'), 'broken');
      expect(catalog.categories.last.id, 'remya-apps');

      catalog.search('bar');
      while (catalog.searching) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(catalog.appResults.single, (
        app: 'remya-bar',
        page: 'layout',
        title: 'Bar height',
      ));
      await catalog.openApp('remya-bar', 'layout');
      expect(service.calls.last.$2, ['remya-bar', 'layout']);
    },
  );

  testWidgets('Remya apps category and app search results open apps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: SettingsShell(catalog: catalog)));
    await tester.tap(find.byKey(const ValueKey('nav-remya-apps')));
    await tester.pumpAndSettle();
    expect(find.text('Remya Bar'), findsOneWidget);
    expect(find.textContaining('missing field `config`'), findsOneWidget);
    // A rejected registration cannot open, so only the valid app has the action.
    expect(find.text('Open settings'), findsOneWidget);
    await tester.tap(find.text('Layout'));
    await tester.pumpAndSettle();
    expect(service.calls.last.$2, ['remya-bar', 'layout']);

    await tester.enterText(
      find.byKey(const ValueKey('settings-search')),
      'bar',
    );
    await tester.pumpAndSettle();
    expect(find.text('Bar height'), findsOneWidget);
    expect(
      find.textContaining('Opens in the Remya Bar settings window'),
      findsOneWidget,
    );
    await tester.tap(find.text('Bar height'));
    await tester.pumpAndSettle();
    expect(service.calls.last.$2, ['remya-bar', 'layout']);
  });

  testWidgets('failed page load keeps the previous page and retries', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    service.failure = StateError('Core unavailable');
    await tester.pumpWidget(MaterialApp(home: SettingsShell(catalog: catalog)));
    await tester.tap(find.byKey(const ValueKey('nav-system')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open Display'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-group-system')), findsOneWidget);
    service.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not open'), findsNothing);
    expect(find.text('Screens'), findsOneWidget);
  });
}
