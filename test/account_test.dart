import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_settings/features/account/presentation/account_information_page.dart';
import 'package:remya_settings/features/settings/domain/settings_catalog.dart';
import 'package:remya_ui/settings_ui.dart';

import 'support/catalog.dart';

void main() {
  testWidgets('account information keeps the username read-only', (
    tester,
  ) async {
    final catalog = SettingsCatalog.fromJson(readCatalog());
    final controller = RemyaAccountController(
      read: () async => {'username': 'test-user'},
      save: (_, _) => throw StateError('Unexpected write'),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AccountInformationPage(
              page: catalog.page('your-info'),
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('test-user'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
