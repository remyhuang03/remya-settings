import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/settings/presentation/settings_list.dart';

void main() {
  testWidgets(
    'large lists build lazily inside a bounded independent viewport',
    (tester) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final built = <int>{};
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const .only(top: 100, bottom: 24),
                  child: SettingsList(
                    title: 'Items',
                    actions: const [
                      SizedBox(width: 120, child: Text('Search')),
                    ],
                    itemCount: 10000,
                    itemExtent: 48,
                    empty: const Text('Empty'),
                    itemBuilder: (_, index) {
                      built.add(index);
                      return Text('Item $index');
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.getBottomLeft(find.byType(ListView)).dy, 776);
      expect(tester.getTopLeft(find.text('Items')).dx, 20);
      expect(tester.getTopRight(find.text('Search')).dx, 880);
      expect(built.length, lessThan(100));
      final header = tester.getTopLeft(find.text('Items'));
      await tester.drag(find.byType(ListView), const Offset(0, -800));
      await tester.pumpAndSettle();
      expect(built.any((index) => index > 20), isTrue);
      expect(built.length, lessThan(100));
      expect(tester.getTopLeft(find.text('Items')), header);
      tester.view.physicalSize = const Size(600, 1100);
      await tester.pump();
      await tester.pump();
      expect(tester.getTopRight(find.text('Search')).dx, 580);
      expect(
        tester.getCenter(find.text('Search')).dy,
        tester.getCenter(find.text('Items')).dy,
      );
      expect(tester.getBottomLeft(find.byType(ListView)).dy, 1076);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('narrow headers wrap and empty lists fit bounded dialog space', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 420,
              child: SettingsList(
                title: 'Items',
                actions: const [
                  SizedBox(width: 232, child: TextField()),
                  SizedBox(width: 232, child: Text('Filter')),
                ],
                itemCount: 0,
                empty: const Text('Empty'),
                itemBuilder: (_, _) => throw StateError('No items'),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(SettingsList)).height, 420);
    expect(
      tester.getTopLeft(find.byType(TextField)).dy,
      greaterThan(tester.getBottomLeft(find.text('Items')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Filter')).dy,
      greaterThan(tester.getBottomLeft(find.byType(TextField)).dy),
    );
    expect(find.text('Empty'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh and reorder retain search focus and row expansion', (
    tester,
  ) async {
    final items = ValueNotifier([1, 2]);
    addTearDown(items.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder(
              valueListenable: items,
              builder: (context, values, _) => SettingsList(
                title: 'Items',
                actions: const [SizedBox(width: 232, child: TextField())],
                itemCount: values.length,
                empty: const Text('Empty'),
                findChildIndexCallback: (key) {
                  final index = values.indexWhere(
                    (id) => PageStorageKey('row-$id') == key,
                  );
                  return index < 0 ? null : index;
                },
                itemBuilder: (_, index) => ExpansionTile(
                  key: PageStorageKey('row-${values[index]}'),
                  title: Text('Row ${values[index]}'),
                  children: [Text('Detail ${values[index]}')],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Row 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'draft');
    items.value = [2, 1];
    await tester.pumpAndSettle();
    expect(find.text('Detail 1').hitTestable(), findsOneWidget);
    final input = tester.widget<EditableText>(find.byType(EditableText));
    expect(input.controller.text, 'draft');
    expect(input.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });
}
