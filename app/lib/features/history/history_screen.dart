import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../config/env.dart';
import '../../data/models.dart';
import '../../providers.dart';
import '../../ui/widgets.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryRange _range = HistoryRange.day;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider(_range));

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: RefreshIndicator.adaptive(
        onRefresh: () => ref.refresh(historyProvider(_range).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            PageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<HistoryRange>(
                    segments: [
                      for (final r in HistoryRange.values)
                        ButtonSegment(value: r, label: Text(r.label)),
                    ],
                    selected: {_range},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() => _range = s.first),
                  ),
                  const SizedBox(height: 16),
                  history.when(
                    skipLoadingOnReload: true,
                    loading: () => const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    ),
                    error: (e, _) => ErrorView(
                      error: e,
                      onRetry: () => ref.invalidate(historyProvider(_range)),
                    ),
                    data: (h) => _Charts(history: h, range: _range),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Charts extends StatelessWidget {
  const _Charts({required this.history, required this.range});

  final History history;
  final HistoryRange range;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = Theme.of(context).colorScheme;

    if (history.points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.show_chart, size: 48, color: c.outline),
            const SizedBox(height: 12),
            Text('No readings in the last ${range.label} yet', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The device saves a reading every 5 minutes while it is online.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final shots = history.shots.map((e) => e.createdAt).toList();
    final cards = [
      _ChartCard(
        title: 'Soil moisture',
        icon: Icons.grass,
        unit: '%',
        color: c.primary,
        history: history,
        range: range,
        value: (p) => p.soilPct,
        minY: 0,
        maxY: 100,
        thresholds: const [DeviceRules.soilStartPct, DeviceRules.soilStopPct],
        shots: shots,
        footnote: shots.isEmpty
            ? null
            : 'Blue lines: pump shots (${shots.length} in the last ${range.label})',
      ),
      _ChartCard(
        title: 'Temperature',
        icon: Icons.thermostat,
        unit: ' °C',
        color: const Color(0xFFE0892B),
        history: history,
        range: range,
        value: (p) => p.tempC,
      ),
      _ChartCard(
        title: 'Humidity',
        icon: Icons.cloud_outlined,
        unit: '%',
        color: c.secondary,
        history: history,
        range: range,
        value: (p) => p.humidity,
        minY: 0,
        maxY: 100,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      // Tablets: soil full width, temperature and humidity side by side.
      if (constraints.maxWidth >= 720) {
        return Column(
          children: [
            cards[0],
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[1]),
                const SizedBox(width: 16),
                Expanded(child: cards[2]),
              ],
            ),
          ],
        );
      }
      return Column(
        children: [
          for (final card in cards) ...[card, const SizedBox(height: 16)],
        ],
      );
    });
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.icon,
    required this.unit,
    required this.color,
    required this.history,
    required this.range,
    required this.value,
    this.minY,
    this.maxY,
    this.thresholds = const [],
    this.shots = const [],
    this.footnote,
  });

  final String title;
  final IconData icon;
  final String unit;
  final Color color;
  final History history;
  final HistoryRange range;
  final double? Function(HistoryPoint) value;
  final double? minY;
  final double? maxY;
  final List<int> thresholds;
  final List<DateTime> shots;
  final String? footnote;

  double _x(DateTime t) => t.difference(history.since).inSeconds / 60;

  DateTime _time(double x) => history.since.add(Duration(seconds: (x * 60).round()));

  String _label(double x) {
    final t = _time(x);
    return switch (range) {
      HistoryRange.day => DateFormat.Hm().format(t),
      HistoryRange.week => DateFormat.E().format(t),
      HistoryRange.month => DateFormat('d/M').format(t),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Points, with a gap wherever the device was offline (missing buckets).
    final spots = <FlSpot>[];
    final values = <double>[];
    DateTime? previous;
    final maxGap = Duration(minutes: range.bucketMinutes * 3);
    for (final p in history.points) {
      final v = value(p);
      if (v == null) continue;
      if (previous != null && p.time.difference(previous) > maxGap) {
        spots.add(FlSpot.nullSpot);
      }
      spots.add(FlSpot(_x(p.time), v));
      values.add(v);
      previous = p.time;
    }

    if (values.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('$title: no data', style: text.bodyMedium),
        ),
      );
    }

    final lo = values.reduce(math.min);
    final hi = values.reduce(math.max);
    final avg = values.reduce((a, b) => a + b) / values.length;
    final yMin = minY ?? (lo - 2).floorToDouble();
    final yMax = maxY ?? (hi + 2).ceilToDouble();
    final maxX = range.duration.inMinutes.toDouble();
    String fmt(double v) => unit == '%' ? v.round().toString() : v.toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: text.titleMedium)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'min ${fmt(lo)}$unit · avg ${fmt(avg)}$unit · max ${fmt(hi)}$unit',
              style: text.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Semantics(
                label: '$title chart for the last ${range.label}. '
                    'Minimum ${fmt(lo)}$unit, average ${fmt(avg)}$unit, maximum ${fmt(hi)}$unit.',
                child: LineChart(
                  LineChartData(
                    minX: 0,
                    maxX: maxX,
                    minY: yMin,
                    maxY: yMax,
                    clipData: const FlClipData.all(),
                    gridData: FlGridData(
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) =>
                          FlLine(color: c.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(),
                      rightTitles: const AxisTitles(),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(fmt(v), style: text.labelSmall),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: maxX / 4,
                          getTitlesWidget: (v, meta) => SideTitleWidget(
                            meta: meta,
                            child: Text(_label(v), style: text.labelSmall),
                          ),
                        ),
                      ),
                    ),
                    extraLinesData: ExtraLinesData(
                      horizontalLines: [
                        for (final t in thresholds)
                          HorizontalLine(
                            y: t.toDouble(),
                            color: c.onSurfaceVariant.withValues(alpha: 0.5),
                            strokeWidth: 1,
                            dashArray: const [4, 4],
                          ),
                      ],
                      verticalLines: [
                        for (final s in shots)
                          VerticalLine(
                            x: _x(s),
                            color: const Color(0xFF2F80ED).withValues(alpha: 0.35),
                            strokeWidth: 1.5,
                          ),
                      ],
                    ),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (_) => c.inverseSurface,
                        getTooltipItems: (touched) => [
                          for (final t in touched)
                            LineTooltipItem(
                              '${fmt(t.y)}$unit\n${DateFormat('d MMM HH:mm').format(_time(t.x))}',
                              TextStyle(color: c.onInverseSurface, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                    lineBarsData: [
                      LineChartBarData(
                        spots: spots,
                        color: color,
                        barWidth: 2.5,
                        isCurved: true,
                        preventCurveOverShooting: true,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: color.withValues(alpha: 0.12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (footnote != null) ...[
              const SizedBox(height: 8),
              Text(footnote!, style: text.bodySmall?.copyWith(color: c.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
