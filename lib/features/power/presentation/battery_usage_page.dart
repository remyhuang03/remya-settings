import 'package:fl_chart/fl_chart.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:remya_settings_client/settings_contract.dart';

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

  @override
  Widget build(BuildContext context) {
    final h = _history;
    final perApp = widget.page.controls.firstWhere(
      (c) => c.id == 'battery-usage.68bac7d6',
    );
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Text(
          widget.page.description,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        if (_error != null)
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(_error!),
          ),
        Padding(
          padding: const .only(top: 28, bottom: 12),
          child: Text(
            'Battery history',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SettingsSurface(
          padding: .zero,
          child: Column(
            children: [
              SettingRow(
                id: 'battery-usage.2be90408',
                label: const Text('Time frame'),
                control: DropdownMenu<int>(
                  initialSelection: _days,
                  width: 232,
                  enabled: !_busy,
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 1, label: 'Last 24 hours'),
                    DropdownMenuEntry(value: 7, label: 'Last 7 days'),
                  ],
                  onSelected: (v) {
                    if (v != null) {
                      setState(() {
                        _days = v;
                        _history = null;
                      });
                      _load();
                    }
                  },
                ),
              ),
              const Divider(height: 1, indent: 20, endIndent: 20),
              Padding(
                padding: const .all(20),
                child: h == null
                    ? Text(
                        _busy
                            ? 'Loading battery history…'
                            : 'Battery history unavailable',
                      )
                    : h.points.isEmpty
                    ? const Text('No battery samples in this period')
                    : Semantics(
                        label:
                            'Battery level history. ${h.points.length} observations. Latest ${h.points.last.percent.round()} percent.',
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: _BatteryChart(h),
                        ),
                      ),
              ),
              if (h != null && h.durations.values.any((v) => v > 0))
                Padding(
                  padding: const .all(20),
                  child: SizedBox(height: 180, child: _UsageChart(h)),
                ),
              for (final entry in {
                'screen-on': 'Screen on time',
                'screen-off': 'Screen off time',
                'sleep': 'Sleep time',
              }.entries) ...[
                const Divider(height: 1, indent: 20, endIndent: 20),
                SettingRow(
                  id: 'battery-usage-${entry.key}',
                  label: Text(entry.value),
                  control: Text(
                    h == null
                        ? '—'
                        : BatteryHistory.duration(h.durations[entry.key]!),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (h != null)
          Padding(
            padding: const .only(top: 12),
            child: Text(
              'Unobserved: ${BatteryHistory.duration(h.unknown)}. Recording starts when Settings runs. Sampling gaps are not counted as screen or sleep time.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Padding(
          padding: const .only(top: 28, bottom: 12),
          child: Text(
            'Application usage',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        SettingsSurface(padding: .zero, child: SettingControlTile(perApp)),
      ],
    );
  }
}

class _BatteryChart extends StatelessWidget {
  const _BatteryChart(this.history);
  final BatteryHistory history;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hours = (history.to - history.from) / 3600;
    final spots = <FlSpot>[];
    int? previous;
    for (final point in history.points) {
      if (previous != null &&
          (point.time - previous > 90 || point.time < previous)) {
        spots.add(FlSpot.nullSpot);
      }
      spots.add(FlSpot((point.time - history.from) / 3600, point.percent));
      previous = point.time;
    }
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: hours,
        minY: 0,
        maxY: 100,
        borderData: FlBorderData(show: false),
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
              reservedSize: 40,
              interval: 25,
              getTitlesWidget: (v, meta) => Text(
                '${v.round()}%',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: hours / 4,
              getTitlesWidget: (v, meta) => Padding(
                padding: const .only(top: 8),
                child: Text(
                  v == hours ? 'Now' : '−${(hours - v).round()}h',
                  style: Theme.of(context).textTheme.labelSmall,
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
                    '${spot.y.round()}%',
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
            barWidth: 2.5,
            isCurved: false,
            dotData: FlDotData(show: history.points.length == 1),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: .topCenter,
                end: .bottomCenter,
                colors: [
                  colors.primary.withValues(alpha: .18),
                  colors.primary.withValues(alpha: .01),
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

class _UsageChart extends StatelessWidget {
  const _UsageChart(this.history);
  final BatteryHistory history;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final values = history.durations.values.toList();
    final palette = [colors.primary, colors.secondary, colors.tertiary];
    return Semantics(
      label:
          'Observed usage durations: screen on ${BatteryHistory.duration(values[0])}, screen off ${BatteryHistory.duration(values[1])}, sleep ${BatteryHistory.duration(values[2])}.',
      child: BarChart(
        BarChartData(
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (v, meta) => Padding(
                  padding: const .only(top: 8),
                  child: Text(
                    ['Screen on', 'Screen off', 'Sleep'][v.toInt()],
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colors.inverseSurface,
              getTooltipItem: (group, index, rod, rodIndex) => BarTooltipItem(
                BatteryHistory.duration(values[index]),
                TextStyle(color: colors.onInverseSurface, fontWeight: .w600),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < 3; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: values[i] / 3600,
                    color: palette[i],
                    width: 28,
                    borderRadius: const .vertical(top: Radius.circular(8)),
                  ),
                ],
              ),
          ],
        ),
        duration: Duration.zero,
      ),
    );
  }
}
