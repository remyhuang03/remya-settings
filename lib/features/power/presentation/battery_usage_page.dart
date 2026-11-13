import 'package:fl_chart/fl_chart.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:remya_client/settings_contract.dart';

import '../../settings/domain/settings_catalog.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../domain/battery_history.dart';

class BatteryUsagePage extends StatefulWidget {
  const BatteryUsagePage({super.key, required this.client, required this.page});
  final SettingsClient client;
  final SettingsPageSpec page;
  @override
  State<BatteryUsagePage> createState() => _BatteryUsagePageState();
}

class _BatteryUsagePageState extends State<BatteryUsagePage> {
  int _days = 1;
  BatteryHistory? _history;
  String? _error;
  bool _busy = false;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final to = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final from = to - _days * 86400;
      final events = <Map<String, dynamic>>[];
      var after = 0;
      while (true) {
        final result = await widget.client.batteryHistory(
          from: from,
          to: to,
          after: after,
        );
        if (!mounted) return;
        if (after == 0) {
          events.addAll(
            (result['context'] as List? ?? []).cast<Map<String, dynamic>>(),
          );
        }
        final rows = (result['observations'] as List)
            .cast<Map<String, dynamic>>();
        events.addAll(rows);
        if (rows.length < 1000) break;
        final next = result['next'] as int;
        if (next <= after) throw StateError('History cursor did not advance');
        after = next;
      }
      if (mounted) {
        setState(() {
          _history = BatteryHistory(events, from, to);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _states = [
    (key: 'screen-on', id: 'battery-usage.37bfb377', label: 'Screen on'),
    (key: 'screen-off', id: 'battery-usage.1aa63c64', label: 'Screen off'),
    (key: 'sleep', id: 'battery-usage.adee81f9', label: 'Sleep'),
  ];

  void _select(int days) {
    setState(() {
      _days = days;
      _history = null;
    });
    _load();
  }

  Widget _heading(String text) => Padding(
    padding: const .only(top: 28, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );

  @override
  Widget build(BuildContext context) {
    final h = _history;
    final theme = Theme.of(context);
    final perApp = widget.page.controls.firstWhere(
      (c) => c.id == 'battery-usage.68bac7d6',
    );
    final empty = h == null
        ? Text(
            _busy ? 'Loading battery history…' : 'Battery history unavailable',
          )
        : h.points.isEmpty
        ? const Text('No battery samples in this period')
        : null;
    final colors = [
      theme.colorScheme.primary,
      theme.colorScheme.tertiary,
      theme.colorScheme.secondary,
    ];
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(widget.page.description, style: theme.textTheme.bodyLarge),
        const SizedBox(height: 20),
        if (_error case final error?)
          SettingsErrorCard(message: error, onRetry: _busy ? null : _load),
        SettingsSurface(
          padding: .zero,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              SettingRow(
                id: 'battery-usage.2be90408',
                label: const Text('Time frame'),
                control: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('24 hours')),
                    ButtonSegment(value: 7, label: Text('7 days')),
                  ],
                  selected: {_days},
                  showSelectedIcon: false,
                  onSelectionChanged: _busy ? null : (v) => _select(v.single),
                ),
              ),
              const Divider(height: 1, indent: 20, endIndent: 20),
              if (h != null && h.points.isNotEmpty) _Summary(h),
              Padding(
                padding: const .fromLTRB(20, 8, 20, 16),
                child:
                    empty ??
                    Column(
                      crossAxisAlignment: .start,
                      spacing: 12,
                      children: [
                        Semantics(
                          label:
                              'Battery level history. ${h!.points.length} observations. Latest ${h.points.last.percent.round()} percent.',
                          child: SizedBox(height: 200, child: _BatteryChart(h)),
                        ),
                        if (h.pluggedRanges.isNotEmpty)
                          _Legend(
                            color: theme.colorScheme.tertiaryContainer,
                            label: 'Plugged in',
                          ),
                      ],
                    ),
              ),
            ],
          ),
        ),
        _heading('Screen and sleep'),
        SettingsSurface(
          padding: .zero,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              if (h != null)
                Padding(
                  padding: const .fromLTRB(20, 20, 20, 4),
                  child: _ShareBar(
                    parts: [
                      for (var i = 0; i < _states.length; i++)
                        (h.durations[_states[i].key]!, colors[i]),
                      (h.unknown, theme.colorScheme.outlineVariant),
                    ],
                  ),
                ),
              for (var i = 0; i < _states.length; i++)
                SettingRow(
                  id: _states[i].id,
                  label: _Legend(color: colors[i], label: _states[i].label),
                  control: Text(
                    h == null
                        ? '—'
                        : BatteryHistory.duration(h.durations[_states[i].key]!),
                  ),
                ),
              if (h != null && h.unknown > 0)
                SettingRow(
                  id: 'battery-usage-unrecorded',
                  label: _Legend(
                    color: theme.colorScheme.outlineVariant,
                    label: 'Not recorded',
                  ),
                  control: Text(BatteryHistory.duration(h.unknown)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const .only(top: 12),
          child: Text(
            'Recording runs while the Settings service does. Time it was not running is not counted as screen or sleep time.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        _heading('Application usage'),
        SettingsSurface(padding: .zero, child: SettingControlTile(perApp)),
      ],
    );
  }
}

/// The latest level, whether it is charging, and how much was used.
class _Summary extends StatelessWidget {
  const _Summary(this.history);
  final BatteryHistory history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final latest = history.points.last;
    final level = latest.percent.round();
    return Padding(
      padding: const .fromLTRB(20, 20, 20, 8),
      child: Row(
        spacing: 16,
        children: [
          Icon(
            latest.pluggedIn
                ? Icons.battery_charging_full_rounded
                : Icons.battery_std_rounded,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          Text('$level%', style: theme.textTheme.displaySmall),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  latest.pluggedIn ? 'Plugged in' : 'On battery',
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  'Used ${history.drained.round()}% of a full charge in this period',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: .min,
    spacing: 12,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: .circle),
      ),
      Text(label),
    ],
  );
}

/// One rounded bar split by how long each state lasted.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.parts});
  final List<(int, Color)> parts;

  @override
  Widget build(BuildContext context) {
    final shown = parts.where((p) => p.$1 > 0).toList();
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: .circular(8),
        child: SizedBox(
          height: 16,
          child: Row(
            crossAxisAlignment: .stretch,
            spacing: 2,
            children: [
              for (final (seconds, color) in shown)
                Expanded(
                  flex: seconds,
                  child: ColoredBox(color: color),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BatteryChart extends StatelessWidget {
  const _BatteryChart(this.history);
  final BatteryHistory history;

  String _clock(BuildContext context, double hoursAgo) =>
      MaterialLocalizations.of(context).formatTimeOfDay(
        TimeOfDay.fromDateTime(
          DateTime.fromMillisecondsSinceEpoch(
            (history.to - hoursAgo * 3600).round() * 1000,
          ),
        ),
        alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
      );

  /// Axis ticks: clock times for a day, whole days back for a week.
  String _tick(BuildContext context, double hoursAgo, double hours) {
    if (hoursAgo <= 0.01) return 'Now';
    if (hours > 24) return '−${(hoursAgo / 24).round()} d';
    return _clock(context, hoursAgo);
  }

  /// Tooltips name the day too once the point is more than a day back.
  String _moment(BuildContext context, double hoursAgo) {
    final days = hoursAgo ~/ 24;
    final clock = _clock(context, hoursAgo);
    return days == 0 ? clock : '−$days d, $clock';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hours = (history.to - history.from) / 3600;
    double x(int time) => (time - history.from) / 3600;
    final spots = <FlSpot>[];
    int? previous;
    for (final point in history.points) {
      if (previous != null &&
          (point.time - previous > BatteryHistory.maxStep ||
              point.time < previous)) {
        spots.add(FlSpot.nullSpot);
      }
      spots.add(FlSpot(x(point.time), point.percent));
      previous = point.time;
    }
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: hours,
        minY: 0,
        maxY: 100,
        borderData: FlBorderData(show: false),
        rangeAnnotations: RangeAnnotations(
          verticalRangeAnnotations: [
            for (final (start, end) in history.pluggedRanges)
              VerticalRangeAnnotation(
                x1: x(start),
                x2: math.max(x(end), x(start) + hours / 400),
                color: colors.tertiaryContainer.withValues(alpha: .6),
              ),
          ],
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) => FlLine(
            color: colors.outlineVariant.withValues(alpha: .4),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              interval: 25,
              getTitlesWidget: (v, meta) =>
                  Text('${v.round()}%', style: text.labelSmall),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: hours > 24 ? 24 : hours / 4,
              getTitlesWidget: (v, meta) => Padding(
                padding: const .only(top: 8),
                child: Text(
                  _tick(context, hours - v, hours),
                  style: text.labelSmall,
                ),
              ),
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map(
                  (spot) => LineTooltipItem(
                    '${spot.y.round()}%\n${_moment(context, hours - spot.x)}',
                    TextStyle(
                      color: colors.onInverseSurface,
                      fontWeight: .w600,
                    ),
                  ),
                )
                .toList(),
            getTooltipColor: (_) => colors.inverseSurface,
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: colors.primary,
            barWidth: 3,
            isCurved: false,
            isStrokeCapRound: true,
            dotData: FlDotData(show: history.points.length == 1),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: .topCenter,
                end: .bottomCenter,
                colors: [
                  colors.primary.withValues(alpha: .22),
                  colors.primary.withValues(alpha: .02),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}
