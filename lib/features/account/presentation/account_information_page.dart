import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';
import 'package:remya_ui/settings_ui.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';

class AccountInformationPage extends StatelessWidget {
  const AccountInformationPage({
    super.key,
    required this.page,
    required this.controller,
  });

  final SettingsPageSpec page;
  final RemyaAccountController controller;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .stretch,
    children: [
      RemyaAvatarEditor(controller: controller),
      const SettingsSectionTitle('Account'),
      ListenableBuilder(
        listenable: controller,
        builder: (context, _) => SettingsSurface(
          padding: .zero,
          child: settingsRows([
            _Readout(
              id: accountUsernameSettingId,
              title: 'Username',
              value: controller.value['username'] as String?,
            ),
            for (final setting in page.controls.where(
              (s) => !const {
                accountUsernameSettingId,
                accountAvatarSettingId,
              }.contains(s.id),
            ))
              SettingControlTile(setting),
          ]),
        ),
      ),
    ],
  );
}

class _Readout extends StatelessWidget {
  const _Readout({required this.id, required this.title, required this.value});
  final String id;
  final String title;
  final String? value;
  @override
  Widget build(BuildContext context) => SettingRow(
    id: id,
    label: Column(
      crossAxisAlignment: .start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        SelectableText(
          value ?? 'Unavailable',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
