import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/applications/application/appimages_controller.dart';
import 'package:remya_settings/features/applications/presentation/application_icon.dart';
import 'package:remya_settings/features/applications/presentation/application_metadata.dart';
import 'package:remya_settings/features/applications/presentation/appimages_page.dart';

void main() {
  test('byte counts select readable binary units', () {
    expect(formatBytes(0), '0 B');
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1024), '1.0 KiB');
    expect(formatBytes(1536), '1.5 KiB');
    expect(formatBytes(1024 * 1024), '1.0 MiB');
    expect(formatBytes(3 * 1024 * 1024 * 1024), '3.0 GiB');
    expect(applicationSourceLabel('appimage'), 'AppImage');
    expect(applicationSourceLabel('manual'), 'Manual installation');
  });

  testWidgets(
    'AppImage progress surrounds its icon and uses adaptive speed units',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var status = 'downloading';
      final writes = <String>[];
      Map<String, dynamic> state() => {
        'apps': [
          {
            'id': 'A.AppImage',
            'name': 'A',
            'path': '/h/A.AppImage',
            'size': 1024,
            'version': '1.2',
            'integrated': true,
            'source': 'https://github.com/o/r',
            'source_origin': 'custom',
            'updates': true,
            'checked': false,
            'job': {'status': status, 'bytes': 100, 'total': 200, 'speed': 512},
          },
        ],
        'installing': <String>[],
        'directory': '/h',
        'auto_check': true,
        'auto_update': false,
        'last_check': 0,
        'error': null,
      };
      final controller = AppImagesController(
        read: () async => state(),
        write: (id, _) async {
          writes.add(id);
          return {};
        },
        setSource: (_, _, _) async => {},
        formatDate: (value) async => value,
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AppImagesPage(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      final indicator = find.byType(CircularProgressIndicator);
      expect(tester.widget<CircularProgressIndicator>(indicator).value, .5);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('512 B/s'), findsOneWidget);
      expect(
        tester
            .getRect(indicator)
            .contains(tester.getCenter(find.byType(ApplicationIcon))),
        isTrue,
      );
      expect(
        tester.getSize(indicator).width,
        greaterThan(tester.getSize(find.byType(ApplicationIcon)).width),
      );

      await tester.ensureVisible(find.text('A'));
      await tester.tap(find.text('A'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<CircularProgressIndicator>(indicator.last).value,
        .5,
      );
      status = 'checking';
      controller.apply(state());
      await tester.pump();
      expect(
        tester.widget<CircularProgressIndicator>(indicator.last).value,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('appimage-cancel-A.AppImage')).last,
      );
      await tester.pump();
      expect(writes, contains('appimages.cancel'));
      status = 'installing';
      controller.apply(state());
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('appimage-cancel-A.AppImage')).last,
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
