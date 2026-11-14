import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/settings_ui.dart';
import 'package:remya_client/settings_contract.dart';

import 'ai_add_provider_dialog.dart';
import 'ai_provider_detail.dart';
import 'ai_widgets.dart';

/// Providers found on this device and imported API endpoints.
class AiProvidersPage extends StatefulWidget {
  const AiProvidersPage({super.key, required this.client});
  final SettingsClient client;

  @override
  State<AiProvidersPage> createState() => _AiProvidersPageState();
}

class _AiProvidersPageState extends State<AiProvidersPage>
    with AiSettingsReader {
  String? _detail;

  @override
  SettingsClient get client => widget.client;

  Future<void> _add() async {
    final catalog = aiRows(settings?['catalog']);
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => AiAddProviderDialog(client: client, catalog: catalog),
    );
    if (added == true) await run(client.readAi);
  }

  @override
  Widget build(BuildContext context) {
    final providers = aiRows(settings?['providers']);
    if (_detail case final id?) {
      if (providers.where((row) => row['id'] == id).firstOrNull
          case final row?) {
        return AiProviderDetail(
          client: client,
          row: row,
          lowPercent: _lowPercent,
          onBack: () => setState(() => _detail = null),
          onChanged: (operation) => run(operation),
        );
      }
    }
    final codexbar = settings?['codexbar'] as Map?;
    return Column(
      crossAxisAlignment: .stretch,
      spacing: 12,
      children: [
        if (error case final message?)
          SettingsErrorCard(message: message, onRetry: busy ? null : _refresh),
        if (codexbar != null && codexbar['available'] != true)
          const _CodexBarMissing(),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: Text(
                providers.isEmpty && settings != null
                    ? 'No AI providers found on this device'
                    : '${providers.length} on this device',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: busy ? null : _refresh,
              icon: const Icon(Icons.refresh_rounded),
            ),
            FilledButton.icon(
              onPressed: busy || settings == null ? null : _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add provider'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        for (final (index, row) in providers.indexed)
          _ProviderCard(
            key: ValueKey('ai-provider-${row['id']}'),
            row: row,
            index: index,
            lowPercent: _lowPercent,
            onOpen: () => setState(() => _detail = row['id'] as String),
            onTrack: busy || row['kind'] != 'codexbar'
                ? null
                : (enabled) => run(
                    () => client.setAiProvider(
                      row['id'] as String,
                      enabled: enabled,
                    ),
                  ),
          ),
        if (settings != null) _Sources(codexbar: codexbar),
      ],
    );
  }

  int get _lowPercent =>
      ((settings?['bar'] as Map?)?['lowPercent'] as num?)?.toInt() ?? 20;

  Future<void> _refresh() => run(client.readAi);
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    super.key,
    required this.row,
    required this.index,
    required this.lowPercent,
    required this.onOpen,
    required this.onTrack,
  });
  final AiRow row;
  final int index;
  final int lowPercent;
  final VoidCallback onOpen;
  final ValueChanged<bool>? onTrack;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final id = row['id'] as String;
    final name = (row['name'] as String?) ?? id;
    final windows = aiRows(row['windows']).take(2).toList();
    final failed = const {'needs-setup', 'error'}.contains(row['status']);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: .circular(24),
      clipBehavior: .antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const .fromLTRB(20, 16, 12, 16),
          child: Column(
            crossAxisAlignment: .stretch,
            spacing: 12,
            children: [
              Row(
                spacing: 16,
                children: [
                  AiProviderLogo(id: id, name: name),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      spacing: 4,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: .center,
                          children: [
                            Text(name, style: text.titleMedium),
                            if (row['plan'] case final String plan)
                              AiChip(plan),
                            if (aiSourceLabel(row['source']) case final s?)
                              AiChip(s),
                          ],
                        ),
                        Text(
                          aiStatus(row),
                          maxLines: 2,
                          overflow: .ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: failed
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (row['kind'] == 'codexbar')
                    Semantics(
                      label: 'Track $name usage',
                      child: Switch(
                        value: row['enabled'] == true,
                        onChanged: onTrack,
                      ),
                    ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
              if (windows.isNotEmpty && row['enabled'] == true)
                Padding(
                  padding: const .only(left: 56, right: 8),
                  child: Row(
                    spacing: 16,
                    children: [
                      for (final window in windows)
                        Expanded(
                          child: AiQuotaMeter(
                            id: id,
                            window: window,
                            lowPercent: lowPercent,
                            compact: true,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodexBarMissing extends StatelessWidget {
  const _CodexBarMissing();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsSurface(
      child: Row(
        spacing: 16,
        children: [
          Icon(Icons.info_outline_rounded, color: colors.primary),
          const Expanded(
            child: Text(
              'Install codexbar-cli to find subscription providers and track '
              'their usage. Imported API endpoints still work without it.',
            ),
          ),
        ],
      ),
    );
  }
}

class _Sources extends StatelessWidget {
  const _Sources({required this.codexbar});
  final Map? codexbar;

  @override
  Widget build(BuildContext context) => AdvancedSection(
    storageKey: const PageStorageKey('ai-sources'),
    title: 'Data sources',
    icon: Icons.source_outlined,
    child: settingsRows([
      SettingRow(
        id: 'ai-source-codexbar',
        label: _Source(
          'CodexBar',
          codexbar?['available'] == true
              ? 'Version ${codexbar?['version'] ?? 'unknown'}\n'
                    'Detects providers and reads quota windows'
              : 'Not installed',
        ),
      ),
      const SettingRow(
        id: 'ai-source-models-dev',
        label: _Source(
          'models.dev',
          'Provider documentation, API endpoints, models and pricing',
        ),
      ),
      const SettingRow(
        id: 'ai-source-lobe-icons',
        label: _Source(
          'Lobe Icons',
          'Provider logos, which remain trademarks of their owners',
        ),
      ),
    ]),
  );
}

class _Source extends StatelessWidget {
  const _Source(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: .start,
    spacing: 2,
    children: [
      Text(title, style: Theme.of(context).textTheme.titleSmall),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
