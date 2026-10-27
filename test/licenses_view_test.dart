import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/about/presentation/licenses_view.dart';

void main() {
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  void addLicenses() {
    LicenseRegistry.addLicense(
      () => Stream.fromIterable([
        LicenseEntryWithLineBreaks(['zeta', 'Alpha'], 'Shared license text'),
        LicenseEntryWithLineBreaks(['Alpha'], 'Second license text'),
      ]),
    );
  }

  for (final width in [1100.0, 600.0, 360.0]) {
    testWidgets('licenses stay in separate scroll areas at width $width', (
      tester,
    ) async {
      addLicenses();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 700);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: const LicensesView())),
      );
      await tester.pumpAndSettle();
      final alpha = find.byKey(const ValueKey('license-package-Alpha'));
      final zeta = find.byKey(const ValueKey('license-package-zeta'));
      expect(tester.getTopLeft(alpha).dy, lessThan(tester.getTopLeft(zeta).dy));
      expect(tester.widget<ListTile>(alpha).selected, isTrue);
      expect(find.text('2 licenses.'), findsOneWidget);
      final list = tester.getRect(
        find.byKey(const ValueKey('license-packages')),
      );
      final detail = tester.getRect(
        find.byKey(const ValueKey('license-text-Alpha')),
      );
      expect(list.overlaps(detail), isFalse);
      expect(find.text('Shared license text'), findsOneWidget);
      expect(find.text('Second license text'), findsOneWidget);
      await tester.tap(zeta);
      await tester.pumpAndSettle();
      expect(find.text('Shared license text'), findsOneWidget);
      expect(find.text('Second license text'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty license registry has an explicit state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LicensesView())),
    );
    await tester.pumpAndSettle();
    expect(find.text('No licenses found.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('license loading failures are shown without throwing', (
    tester,
  ) async {
    LicenseRegistry.addLicense(() => Stream.error(StateError('Unavailable')));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LicensesView())),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pumpAndSettle();
    expect(find.text('Unable to load licenses.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
