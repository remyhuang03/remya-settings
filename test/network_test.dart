import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/network/application/network_controller.dart';
import 'package:remya_settings/features/network/presentation/known_networks_page.dart';
import 'package:remya_settings/features/network/presentation/network_status_page.dart';
import 'package:remya_settings/features/network/presentation/network_widgets.dart';
import 'package:remya_settings/features/network/presentation/wifi_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';

Map<String, dynamic> _network(String ssid, String security, {String? known}) =>
    {
      'ssid': ssid,
      'security': security,
      'signal': 60,
      'frequency': 2412,
      'in_use': false,
      'known_uuid': known,
    };

Map<String, dynamic> _state({bool wifi = true, List<Map>? adapters}) => {
  'available': true,
  'writable': true,
  'conflict': false,
  'conflicts': <Map>[],
  'wifi_enabled': wifi,
  'wifi_hardware_enabled': true,
  'connectivity': 'full',
  'adapter': 'wlan0',
  'permissions': <String, String>{},
  'devices':
      adapters ??
      [
        {
          'interface': 'wlan0',
          'kind': 'wifi',
          'state': 'disconnected',
          'physical': true,
          'networks': [
            _network('Cafe', 'wpa2'),
            _network('Corp', 'enterprise'),
            _network('Old', 'wep'),
            _network('Saved Corp', 'enterprise', known: 'saved'),
          ],
        },
      ],
  'profiles': [
    {
      'uuid': 'saved',
      'name': 'Home',
      'ssid': 'Home',
      'security': 'wpa2',
      'autoconnect': true,
      'metered': 'automatic',
      'hidden': false,
      'last_connected': 0,
      'active': false,
      'read_only': false,
    },
  ],
};

void main() {
  late SettingsCatalog catalog;
  late List<(String, String)> writes;

  NetworkController controller(Map<String, dynamic> state) => NetworkController(
    read: () async => state,
    write: (id, value) async {
      writes.add((id, value));
      return state;
    },
    resolve: (_) async => state,
    formatDate: (date) async => date,
    readTraffic: () async => {'interface': null},
  )..value = state;

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  Widget wifi(NetworkController network) => host(
    ListenableBuilder(
      listenable: network,
      builder: (_, _) => WifiPage(
        controller: network,
        catalog: catalog,
        page: catalog.page('wifi'),
        onPage: (_) {},
      ),
    ),
  );

  setUpAll(() {
    catalog = SettingsCatalog.fromJson(
      jsonDecode(File('assets/settings/catalog.json').readAsStringSync())
          as Map<String, dynamic>,
    );
  });
  setUp(() => writes = []);

  test('passwords follow the WPA limits', () {
    expect(passwordProblem('short'), isNotNull);
    expect(passwordProblem('long-enough'), isNull);
    expect(passwordProblem('a' * 64), isNull);
    expect(passwordProblem('z' * 64), isNotNull);
  });

  testWidgets(
    'failed writes stay visible and unresolved conflicts block edits',
    (tester) async {
      final state = _state()
        ..['conflict'] = true
        ..['conflicts'] = [
          {'name': 'Home'},
        ];
      final network = NetworkController(
        read: () async => state,
        write: (_, _) async => throw StateError('write denied'),
        resolve: (_) async => throw StateError('resolve denied'),
        formatDate: (date) async => date,
        readTraffic: () async => {'interface': null},
      );
      addTearDown(network.dispose);
      await network.reload();
      expect(network.canChangePreferences, isFalse);
      expect(network.conflictSummary, 'Home');
      await network.set('wifi.enabled', 'false');
      expect(network.errorMessage, contains('write denied'));
      expect(network.isBusy, isFalse);
      await network.applySavedConfiguration();
      expect(network.errorMessage, contains('resolve denied'));
      expect(network.hasConflict, isTrue);
    },
  );

  testWidgets('turning Wi-Fi off hides networks and the switch writes', (
    tester,
  ) async {
    final network = controller(_state(wifi: false));
    addTearDown(network.dispose);
    await tester.pumpWidget(wifi(network));
    expect(find.text('Available networks'), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(writes, contains(('wifi.enabled', 'true')));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('unsupported new networks cannot connect but saved ones can', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    final network = controller(_state());
    addTearDown(network.dispose);
    await tester.pumpWidget(wifi(network));
    FilledButton button(String ssid) => tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(
          ValueKey('network-$ssid-${ssid == 'Old' ? 'wep' : 'enterprise'}'),
        ),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button('Corp').onPressed, isNull);
    expect(button('Old').onPressed, isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('network-Saved Corp-enterprise')),
      160,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(button('Saved Corp').onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the password dialog sends only on a valid password', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    final network = controller(_state());
    addTearDown(network.dispose);
    await tester.pumpWidget(wifi(network));
    await tester.tap(find.text('Connect').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
    await tester.pumpAndSettle();
    expect(find.text('Use 8 to 63 characters'), findsOneWidget);
    expect(writes.where((w) => w.$1 == 'wifi.connect'), isEmpty);
    await tester.enterText(find.byType(TextField), 'long-enough');
    await tester.tap(find.widgetWithText(FilledButton, 'Connect').last);
    await tester.pumpAndSettle();
    final sent = writes.firstWhere((w) => w.$1 == 'wifi.connect').$2;
    expect(jsonDecode(sent), {'ssid': 'Cafe', 'password': 'long-enough'});
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no adapter and a stopped service report instead of sampling', (
    tester,
  ) async {
    final none = controller(_state(adapters: const []));
    addTearDown(none.dispose);
    await tester.pumpWidget(wifi(none));
    expect(find.text('No Wi-Fi adapter was detected'), findsOneWidget);
    final stopped = controller({'available': false})
      ..errorMessage = 'Cannot read NetworkManager';
    addTearDown(stopped.dispose);
    await tester.pumpWidget(
      host(
        NetworkStatusPage(
          controller: stopped,
          catalog: catalog,
          page: catalog.page('network-status'),
          onPage: (_) {},
        ),
      ),
    );
    expect(find.text('Cannot read NetworkManager'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('known networks filter, expand and keep random address planned', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    final network = controller(_state());
    addTearDown(network.dispose);
    await tester.pumpWidget(
      host(
        KnownNetworksPage(
          controller: network,
          page: catalog.page('known-networks'),
        ),
      ),
    );
    expect(find.text('Home'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('known-networks.mac')), findsOneWidget);
    expect(find.text('Planned'), findsWidgets);
    await tester.enterText(
      find.byKey(const ValueKey('known-networks.search')),
      'nothing',
    );
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);
  });

  test('speeds use readable units', () {
    expect(formatSpeed(0), '0 B/s');
    expect(formatSpeed(1500), '1.5 KB/s');
    expect(formatSpeed(2500000), '2.5 MB/s');
  });

  testWidgets('network status shows live speeds from byte counters', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1600));
    var received = 1000;
    final state = _state()
      ..['primary_uuid'] = 'saved'
      ..['devices'] = [
        {
          'interface': 'wlan0',
          'kind': 'wifi',
          'state': 'connected',
          'physical': true,
          'uuid': 'saved',
          'connection': 'Home',
          'ipv4': ['10.0.0.2/24'],
          'dns': <String>[],
          'ipv6': <String>[],
          'networks': <Map>[],
        },
      ];
    final network = NetworkController(
      read: () async => state,
      write: (_, _) async => state,
      resolve: (_) async => state,
      formatDate: (date) async => date,
      readTraffic: () async {
        received += 2000;
        return {'interface': 'wlan0', 'rx_bytes': received, 'tx_bytes': 0};
      },
    )..value = state;
    addTearDown(network.dispose);
    await tester.pumpWidget(
      host(
        NetworkStatusPage(
          controller: network,
          catalog: catalog,
          page: catalog.page('network-status'),
          onPage: (_) {},
        ),
      ),
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Measuring'), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Download'), findsOneWidget);
    expect(find.text('Upload'), findsOneWidget);
    expect(find.text('0 B/s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
