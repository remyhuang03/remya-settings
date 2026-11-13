import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

import '../../settings/presentation/settings_widgets.dart';
import 'ai_widgets.dart';

const _maxPinned = 3;

/// Which providers the Remy'a Bar quota pill shows, and when it warns.
class AiUsagePage extends StatefulWidget {
  const AiUsagePage({super.key, required this.client});
  final SettingsClient client;

  @override
  State<AiUsagePage> createState() => _AiUsagePageState();
}

class _AiUsagePageState extends State<AiUsagePage> with AiSettingsReader {
  double? _dragging;

  @override
  SettingsClient get client => widget.client;

  Map get _bar => (settings?['bar'] as Map?) ?? const {};
  List<String> get _pinned => [
    for (final id in (_bar['pinned'] as List?) ?? const [])
      if (id is String) id,
  ];

  void _pin(List<String> pinned) => run(() => client.setAiBar(pinned: pinned));

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tracked = {
      for (final row in aiRows(settings?['providers']))
        if (row['kind'] == 'codexbar' && row['enabled'] == true)
          row['id'] as String: row,
    };
    final pinned = [
      for (final id in _pinned)
        if (tracked.containsKey(id)) id,
    ];
    final others = [
      for (final id in tracked.keys)
        if (!pinned.contains(id)) id,
    ];
    final low = (_dragging ?? (_bar['lowPercent'] as num?) ?? 20).toDouble();
    final showUsed = _bar['showUsed'] == true;
    final ringOrder = _bar['ringOrder'] == '5h-inner' ? '5h-inner' : '5h-outer';
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        if (error case final message?)
          SettingsErrorCard(
            message: message,
            onRetry: busy ? null : () => run(client.readAi),
          ),
        if (busy) const LinearProgressIndicator(),
        SettingsSectionTitle(
          'Shown in Remy\'a Bar',
          trailing: Text(
            '${pinned.length} of $_maxPinned',
            style: text.labelLarge,
          ),
        ),
        SettingsSurface(
          padding: .zero,
          child: pinned.isEmpty
              ? const Padding(
                  padding: .all(20),
                  child: Text(
                    'No providers pinned. The bar shows the first three '
                    'tracked providers that report usage.',
                  ),
                )
              : ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: pinned.length,
                  onReorderItem: (from, to) {
                    if (busy) return;
                    final next = [...pinned];
                    next.insert(to, next.removeAt(from));
                    _pin(next);
                  },
                  itemBuilder: (context, i) => _ProviderRow(
                    key: ValueKey('ai-pinned-${pinned[i]}'),
                    row: tracked[pinned[i]]!,
                    leading: ReorderableDragStartListener(
                      index: i,
                      enabled: !busy,
                      child: const Icon(Icons.drag_indicator_rounded),
                    ),
                    actions: [
                      if (i > 0)
                        IconButton(
                          tooltip: 'Move up',
                          onPressed: busy
                              ? null
                              : () => _pin(
                                  [...pinned]
                                    ..insert(i - 1, pinned[i])
                                    ..removeAt(i + 1),
                                ),
                          icon: const Icon(Icons.arrow_upward_rounded),
                        ),
                      IconButton(
                        tooltip: 'Hide from bar',
                        onPressed: busy
                            ? null
                            : () => _pin([...pinned]..removeAt(i)),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                    ],
                  ),
                ),
        ),
        if (others.isNotEmpty) ...[
          const SettingsSectionTitle('Other tracked providers'),
          SettingsSurface(
            padding: .zero,
            child: settingsRows([
              for (final id in others)
                _ProviderRow(
                  key: ValueKey('ai-other-$id'),
                  row: tracked[id]!,
                  subtitle: pinned.length >= _maxPinned
                      ? 'Hide a pinned provider to show this one'
                      : null,
                  actions: [
                    TextButton.icon(
                      onPressed: busy || pinned.length >= _maxPinned
                          ? null
                          : () => _pin([...pinned, id]),
                      icon: const Icon(Icons.push_pin_outlined),
                      label: const Text('Show in bar'),
                    ),
                  ],
                ),
            ]),
          ),
        ],
        const SettingsSectionTitle('Bar display'),
        SettingsSurface(
          padding: .zero,
          child: settingsRows([
            SettingRow(
              id: 'ai-show-used',
              label: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text('Quota metric', style: text.titleSmall),
                  Text(
                    'Show remaining quota or used quota in Remy\'a Bar',
                    style: text.bodySmall,
                  ),
                ],
              ),
              control: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('Remaining')),
                  ButtonSegment(value: true, label: Text('Used')),
                ],
                selected: {showUsed},
                onSelectionChanged: busy || settings == null
                    ? null
                    : (values) =>
                          run(() => client.setAiBar(showUsed: values.first)),
              ),
            ),
            SettingRow(
              id: 'ai-ring-order',
              label: Column(
                crossAxisAlignment: .start,
                spacing: 2,
                children: [
                  Text('Quota rings', style: text.titleSmall),
                  Text(
                    'Choose whether 5h or 1w sits on the outer ring',
                    style: text.bodySmall,
                  ),
                ],
              ),
              control: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: '5h-outer',
                    label: Text('Outer 5h / Inner 1w'),
                  ),
                  ButtonSegment(
                    value: '5h-inner',
                    label: Text('Inner 5h / Outer 1w'),
                  ),
                ],
                selected: {ringOrder},
                onSelectionChanged: busy || settings == null
                    ? null
                    : (values) =>
                          run(() => client.setAiBar(ringOrder: values.first)),
              ),
            ),
          ]),
        ),
        const SettingsSectionTitle('Alerts'),
        SettingsSurface(
          padding: .zero,
          child: SettingRow(
            id: 'ai-low-percent',
            label: Column(
              crossAxisAlignment: .start,
              spacing: 2,
              children: [
                Text('Low quota warning', style: text.titleSmall),
                Text(
                  'Warn when a window has ${low.round()}% or less left',
                  style: text.bodySmall,
                ),
              ],
            ),
            control: SizedBox(
              width: 220,
              child: Slider(
                value: low.clamp(5, 50),
                min: 5,
                max: 50,
                divisions: 9,
                label: '${low.round()}%',
                onChanged: busy || settings == null
                    ? null
                    : (value) => setState(() => _dragging = value),
                onChangeEnd: busy || settings == null
                    ? null
                    : (value) {
                        setState(() => _dragging = null);
                        run(() => client.setAiBar(lowPercent: value.round()));
                      },
              ),
            ),
          ),
        ),
        Padding(
          padding: const .only(top: 16),
          child: Text(
            'Usage comes from CodexBar. Track providers on the Providers page.',
            style: text.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    super.key,
    required this.row,
    required this.actions,
    this.leading,
    this.subtitle,
  });
  final AiRow row;
  final List<Widget> actions;
  final Widget? leading;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final id = row['id'] as String;
    final name = (row['name'] as String?) ?? id;
    return Padding(
      padding: const .symmetric(horizontal: 16, vertical: 10),
      child: Row(
        spacing: 12,
        children: [
          ?leading,
          AiProviderLogo(id: id, name: name, size: 36),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(name, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle case final text?)
                  Text(text, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
