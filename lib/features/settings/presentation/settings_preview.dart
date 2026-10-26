import 'package:material_ui/material_ui.dart';

import 'settings_widgets.dart';

class SettingsPreview extends StatelessWidget {
  const SettingsPreview(this.kind, {super.key});
  final String kind;

  @override
  Widget build(BuildContext context) {
    if (kind == 'none') return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    if (kind == 'display') return const _DisplayPreview();
    if (kind == 'personalization') return const _ThemePreview();
    final (icon, title, detail) = switch (kind) {
      'sound' => (
        Icons.graphic_eq_rounded,
        '为每一种声音，留出空间',
        '输出、输入和应用音量 · 尚未读取音频设备',
      ),
      'network' => (Icons.wifi_rounded, '连接你的世界', '连接状态待接入 · 不扫描或连接网络'),
      'devices' => (
        Icons.devices_other_rounded,
        '设备，井然有序',
        '外设目录待接入 · 不扫描或配对设备',
      ),
      'power' => (Icons.battery_charging_full_rounded, '让能量恰到好处', '电源和电池状态待接入'),
      'storage' => (Icons.storage_rounded, '为重要的东西腾出空间', '所有容量均为示例 · 不扫描或清理文件'),
      'update' => (
        Icons.security_update_good_rounded,
        '让系统持续焕新',
        '更新服务尚未接入 · 不下载或安装更新',
      ),
      _ => (Icons.settings_outlined, '设置预览', '功能尚未接入'),
    };
    return SettingsSurface(
      child: Row(
        children: [
          Container(
            padding: const .all(18),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: .circular(24),
            ),
            child: Icon(icon, size: 38, color: colors.onPrimaryContainer),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DisplayPreview extends StatelessWidget {
  const _DisplayPreview();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsSurface(
      child: Column(
        children: [
          const Align(alignment: .centerLeft, child: Text('显示器排列 · 示意图')),
          const SizedBox(height: 24),
          SizedBox(
            height: 160,
            child: FittedBox(
              child: Row(
                crossAxisAlignment: .end,
                children: [
                  _Monitor(
                    number: '1',
                    width: 230,
                    height: 140,
                    color: colors.primaryContainer,
                  ),
                  const SizedBox(width: 14),
                  _Monitor(
                    number: '2',
                    width: 165,
                    height: 110,
                    color: colors.secondaryContainer,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: .center,
            children: [
              OutlinedButton(onPressed: null, child: Text('标识')),
              OutlinedButton(onPressed: null, child: Text('检测')),
              Text('显示器尚未检测，排列不可拖动'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Monitor extends StatelessWidget {
  const _Monitor({
    required this.number,
    required this.width,
    required this.height,
    required this.color,
  });
  final String number;
  final double width;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: color,
          borderRadius: .circular(18),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 5,
          ),
        ),
        child: Center(
          child: Text(number, style: Theme.of(context).textTheme.displaySmall),
        ),
      ),
      Container(
        width: 10,
        height: 12,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      Container(
        width: width / 3,
        height: 5,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.outlineVariant,
          borderRadius: .circular(3),
        ),
      ),
    ],
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsSurface(
      child: Column(
        crossAxisAlignment: .start,
        children: [
          Text('属于你的桌面', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          Container(
            height: 156,
            clipBehavior: .antiAlias,
            decoration: BoxDecoration(
              borderRadius: .circular(20),
              gradient: LinearGradient(
                begin: .topLeft,
                end: .bottomRight,
                colors: [colors.tertiaryContainer, colors.primaryContainer],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -36,
                  top: -65,
                  child: Container(
                    width: 235,
                    height: 235,
                    decoration: BoxDecoration(
                      shape: .circle,
                      color: colors.primary.withValues(alpha: .12),
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  top: 24,
                  child: Container(
                    width: 125,
                    height: 83,
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: .85),
                      borderRadius: .circular(16),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.primary,
                      size: 34,
                    ),
                  ),
                ),
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 16,
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: .7),
                      borderRadius: .circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in [
                colors.primary,
                colors.tertiary,
                colors.secondary,
                colors.outline,
              ])
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: color, shape: .circle),
                ),
              Text(
                '主题示意 · 尚不可应用',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
