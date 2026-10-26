import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/app.dart';

void main() {
  testWidgets('starts with an empty Material 3 window', (tester) async {
    await tester.pumpWidget(const RemyaSettingsApp());

    expect(find.text("Remy'a Settings"), findsOneWidget);
    final scaffold = tester.element(find.byType(Scaffold));
    expect(Theme.of(scaffold).useMaterial3, isTrue);
    expect(tester.takeException(), isNull);
  });
}
