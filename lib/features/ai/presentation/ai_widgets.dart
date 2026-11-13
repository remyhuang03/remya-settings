import 'dart:async';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remya_ui/ai_identity.dart';
import 'package:remya_client/settings_contract.dart';

typedef AiRow = Map<String, dynamic>;

List<AiRow> aiRows(Object? value) => [
  for (final row in (value as List?) ?? const [])
    if (row is Map) Map<String, dynamic>.from(row),
];

/// Loads `ai.providers` and follows every `ai.*` change from the service.
mixin AiSettingsReader<T extends StatefulWidget> on State<T> {
  SettingsClient get client;
  Map<String, dynamic>? settings;
  String? error;
  bool busy = false;
  StreamSubscription<SettingsChange>? _changes;

  @override
  void initState() {
    super.initState();
    _changes = client.changes.listen((change) {
      if (change.topic == aiProvidersSettingId && !busy) {
        if (change.value['value'] case final Map value) {
          setState(() => settings = Map<String, dynamic>.from(value));
        }
      }
    }, onError: (Object _) {});
    unawaited(run(client.readAi));
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  /// Runs one service operation; a failure keeps the last valid state.
  Future<void> run(Future<Map<String, dynamic>> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final (value, _) = await (operation(), loadAiIdentity()).wait;
      if (mounted) setState(() => settings = value);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// A provider's colored brand mark, or its initials on its accent color.
class AiProviderLogo extends StatelessWidget {
  const AiProviderLogo({
    super.key,
    required this.id,
    required this.name,
    this.size = 40,
  });
  final String id;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = aiProviderIcon(id);
    final accent = aiProviderAccent(id, colors);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: .all(size * .2),
        decoration: BoxDecoration(
          color: icon == null
              ? Color.alphaBlend(accent.withValues(alpha: .24), colors.surface)
              : colors.surfaceContainerHigh,
          shape: .circle,
        ),
        alignment: .center,
        child: icon == null
            ? FittedBox(
                child: Text(
                  aiInitials(name),
                  style: TextStyle(color: colors.onSurface, fontWeight: .w700),
                ),
              )
            : SvgPicture.asset(
                icon,
                width: size * .6,
                height: size * .6,
                // Mono marks draw with currentColor; color marks ignore it.
                theme: SvgTheme(currentColor: colors.onSurface),
              ),
      ),
    );
  }
}

String aiInitials(String name) {
  final words = name.split(RegExp(r'[\s\-_.]+')).where((w) => w.isNotEmpty);
  final letters = words.length > 1
      ? words.take(2).map((w) => w[0]).join()
      : name.substring(0, name.length.clamp(0, 2));
  return letters.toUpperCase();
}

/// A short, honest status line for a provider row.
String aiStatus(AiRow row) => switch (row['status']) {
  'custom' => 'API endpoint',
  'needs-setup' => 'Sign in or add a credential',
  'error' => (row['error'] as String?) ?? 'Usage unavailable',
  _ when row['enabled'] != true => 'Not tracked',
  _ => 'Tracking usage',
};

String? aiSourceLabel(Object? source) => switch (source) {
  'oauth' => 'OAuth',
  'cli' => 'CLI',
  'api' => 'API',
  'web' => 'Web',
  _ => null,
};

String aiWindowLabel(AiRow window) {
  if (window['label'] case final String label when label.isNotEmpty) {
    return label;
  }
  return switch (window['windowMinutes']) {
    final num m when m <= 300 => '${(m / 60).round()}h',
    final num m when m <= 1440 => 'Day',
    final num m when m <= 10080 => 'Week',
    num() => 'Month',
    _ => 'Usage',
  };
}

/// Remaining share of a window, 0..1, or null for an unreadable value.
double? aiLeft(AiRow window) => switch (window['usedPercent']) {
  final num used => (100 - used).clamp(0, 100) / 100,
  _ => null,
};

/// "Resets in 2h 31m"; null when the reset time is unknown or past.
String? aiResetIn(AiRow window, [DateTime? now]) {
  final at = DateTime.tryParse('${window['resetsAt']}');
  if (at == null) return null;
  final left = at.difference(now ?? DateTime.now());
  if (left.isNegative) return null;
  final text = left.inDays > 0
      ? '${left.inDays}d ${left.inHours % 24}h'
      : left.inHours > 0
      ? '${left.inHours}h ${left.inMinutes % 60}m'
      : '${left.inMinutes.clamp(1, 59)}m';
  return 'Resets in $text';
}

/// One quota window as a labeled meter in the provider's accent color.
class AiQuotaMeter extends StatelessWidget {
  const AiQuotaMeter({
    super.key,
    required this.id,
    required this.window,
    required this.lowPercent,
    this.compact = false,
  });
  final String id;
  final AiRow window;
  final int lowPercent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final left = aiLeft(window);
    final low = left != null && left * 100 <= lowPercent;
    final color = low ? colors.error : aiProviderAccent(id, colors);
    final label = aiWindowLabel(window);
    final percent = left == null ? '—' : '${(left * 100).round()}% left';
    return Semantics(
      label: '$label, $percent',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: .stretch,
          spacing: compact ? 4 : 6,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: text.labelLarge)),
                Text(
                  percent,
                  style: (compact ? text.labelLarge : text.titleMedium)
                      ?.copyWith(color: low ? colors.error : null),
                ),
              ],
            ),
            LinearProgressIndicator(
              value: left ?? 0,
              minHeight: compact ? 4 : 8,
              color: color,
              backgroundColor: colors.secondaryContainer,
              borderRadius: .circular(4),
            ),
            if (aiResetIn(window) case final reset? when !compact)
              Text(reset, style: text.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// A small tonal label such as a plan or a source.
class AiChip extends StatelessWidget {
  const AiChip(this.label, {super.key, this.error = false});
  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const .symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.secondaryContainer,
        borderRadius: .circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: error ? colors.onErrorContainer : colors.onSecondaryContainer,
        ),
      ),
    );
  }
}

/// An obscured single-line secret field with a show/hide toggle.
class AiSecretField extends StatefulWidget {
  const AiSecretField({
    super.key,
    required this.controller,
    required this.label,
    this.autofocus = false,
  });
  final TextEditingController controller;
  final String label;
  final bool autofocus;

  @override
  State<AiSecretField> createState() => _AiSecretFieldState();
}

class _AiSecretFieldState extends State<AiSecretField> {
  bool _shown = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    autofocus: widget.autofocus,
    obscureText: !_shown,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: widget.label,
      suffixIcon: IconButton(
        tooltip: _shown ? 'Hide' : 'Show',
        onPressed: () => setState(() => _shown = !_shown),
        icon: Icon(
          _shown ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        ),
      ),
    ),
  );
}
