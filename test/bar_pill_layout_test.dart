import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/appearance/presentation/bar_pill_layout.dart';
import 'package:remya_settings_client/settings_contract.dart';

void main() {
  const layout = BarLayout(
    groups: [
      ['window', 'resources'],
      ['clock'],
      ['sidebar'],
    ],
    center: 1,
  );

  test('pill moves keep the centered group and drop empty groups', () {
    expect(layout.movePill('window', 0, 1).groups.first, [
      'resources',
      'window',
    ]);
    final merged = layout.movePill('clock', 2, 0);
    expect(merged.groups, [
      ['window', 'resources'],
      ['clock', 'sidebar'],
    ]);
    expect(merged.center, isNull);
    final added = layout.movePill('battery', 3);
    expect(added.groups.last, ['battery']);
    expect(added.center, 1);
    final hidden = layout.hidePill('window').hidePill('resources');
    expect(hidden.groups, [
      ['clock'],
      ['sidebar'],
    ]);
    expect(hidden.center, 0);
  });

  test('groups reorder and remove with the centered group', () {
    final moved = layout.moveGroup(1, 2);
    expect(moved.groups.last, ['clock']);
    expect(moved.center, 2);
    final removed = layout.removeGroup(0);
    expect(removed.hidden, contains('window'));
    expect(removed.center, 0);
    expect(layout.withCenter(null).center, isNull);
  });

  test('layout JSON round-trips and reports hidden pills', () {
    expect(BarLayout.fromJson(layout.toJson()), layout);
    expect(BarLayout.defaults.toJson().containsKey('center'), isFalse);
    expect(BarLayout.fromJson(BarLayout.defaults.toJson()).hidden, isEmpty);
    expect(layout.hidden, [
      'notifications',
      'media',
      'workspaces',
      'tray',
      'battery',
    ]);
    expect(() => BarLayout.fromJson({'groups': []}), throwsFormatException);
  });

  test('media marquee defaults off and survives layout edits', () {
    final older = layout.toJson()..remove('media_marquee');
    expect(BarLayout.fromJson(older).mediaMarquee, isFalse);
    expect(
      () => BarLayout.fromJson({...older, 'media_marquee': 'true'}),
      throwsFormatException,
    );
    final enabled = layout.copyWith(mediaMarquee: true).movePill('media', 0);
    expect(BarLayout.fromJson(enabled.toJson()).mediaMarquee, isTrue);
  });

  testWidgets('editor drags pills into new groups and edits groups', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BarLayout? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BarPillLayoutEditor(
              layout: layout,
              showSeconds: true,
              onChanged: (next) => changed = next,
            ),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Clock')),
    );
    await gesture.moveBy(const Offset(20, 20));
    await gesture.moveTo(
      tester.getCenter(find.text('Drop a pill here to add a group')),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(changed!.groups.last, ['clock']);
    expect(changed!.center, isNull);

    await tester.tap(find.byTooltip('Center on bar').first);
    expect(changed!.center, 0);
    await tester.tap(find.byTooltip('Remove group').first);
    expect(changed!.groups, [
      ['clock'],
      ['sidebar'],
    ]);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.delete_outline_rounded).last,
          )
          .onPressed,
      isNull,
    );
  });
}
