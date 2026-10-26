import 'package:material_ui/material_ui.dart';

import '../../settings/presentation/settings_widgets.dart';

const appVersion = '0.1.0+1';
const repositoryUrl = 'https://github.com/remyhuang03/remya_settings';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        SettingsSurface(
          child: Column(
            children: [
              const SizedBox(height: 16),
              Image.asset(
                'assets/icons/settings.png',
                width: 104,
                height: 104,
                semanticLabel: "Remy'a Settings 应用图标",
              ),
              const SizedBox(height: 20),
              Text(
                "Remy'a Settings",
                style: text.headlineMedium,
                textAlign: .center,
              ),
              const SizedBox(height: 8),
              Text(
                '适用于 Hyprland 的全局系统设置',
                style: text.bodyLarge,
                textAlign: .center,
              ),
              const SizedBox(height: 12),
              const Chip(label: Text('v$appVersion · UI Preview')),
              const SizedBox(height: 16),
              const Text(
                'Windows Settings 的组织方式，Material Design 3 Expressive 的视觉语言。',
                textAlign: .center,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSurface(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text('项目状态', style: text.titleMedium),
              const SizedBox(height: 12),
              const Text('目前提供分类浏览、设置搜索、页面预览和许可查看。所有系统设置均未接入；示例值不是设备的当前状态。'),
              const SizedBox(height: 14),
              const Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  AvailabilityBadge(.available),
                  AvailabilityBadge(.planned),
                  AvailabilityBadge(.unsupported),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSurface(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text('仓库', style: text.titleMedium),
              const SizedBox(height: 8),
              const SelectableText(repositoryUrl),
              const SizedBox(height: 8),
              const Text('Private repository · 访问需要仓库权限。可选择并复制地址。'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('第三方开源许可'),
                subtitle: const Text('查看 Flutter 与依赖包的许可声明'),
                trailing: const AvailabilityBadge(.available),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: "Remy'a Settings",
                  applicationVersion: appVersion,
                  applicationIcon: Padding(
                    padding: const .all(16),
                    child: Image.asset(
                      'assets/icons/settings.png',
                      width: 64,
                      height: 64,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              const ListTile(
                leading: Icon(Icons.policy_outlined),
                title: Text('项目许可证'),
                subtitle: Text(
                  'PolyForm Noncommercial License 1.0.0\n项目图标由项目所有者提供。',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
