import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/format.dart';
import '../models/analytics_models.dart';

/// Categorical series colours - a validated colour-blind-safe order, with
/// separate steps for light and dark surfaces. Assigned in fixed order, never cycled.
class SeriesColors {
  static const _light = [
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
    Color(0xFF008300), // green
    Color(0xFF4A3AA7), // violet
    Color(0xFFE34948), // red
  ];
  static const _dark = [
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
    Color(0xFF008300),
    Color(0xFF9085E9),
    Color(0xFFE66767),
  ];

  static Color of(BuildContext context, int slot) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return (dark ? _dark : _light)[slot % 8];
  }

  // Fixed meaning across every chart in the app: the same measure, the same colour.
  static Color sales(BuildContext c) => of(c, 0);
  static Color expenses(BuildContext c) => of(c, 1);
  static Color collected(BuildContext c) => of(c, 2);
}

/// ₹950, ₹12.5K, ₹3.2L, ₹1.1Cr - the way Indian shops read big numbers.
/// (intl's en_IN compact form prints "T" for thousand, which reads as trillion.)
String compactRs(num v) {
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  String f(double x) => x >= 100 || x == x.roundToDouble()
      ? x.toStringAsFixed(0)
      : x.toStringAsFixed(1);
  if (a < 1000) return '$sign₹${f(a.toDouble())}';
  if (a < 100000) return '$sign₹${f(a / 1000)}K';
  if (a < 10000000) return '$sign₹${f(a / 100000)}L';
  return '$sign₹${f(a / 10000000)}Cr';
}

/// Headline number tile.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.accent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = accent ?? scheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 16, color: c),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: TextStyle(
                        fontSize: 21, fontWeight: FontWeight.w800, color: scheme.onSurface)),
              ),
              if (caption != null)
                Text(caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid of KPI tiles that adds columns on wider screens.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 4 : c.maxWidth >= 560 ? 3 : 2;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: cols == 2 ? 1.45 : 1.6,
            children: children,
          );
        },
      );
}

/// A titled card that holds one chart.
class ChartCard extends StatelessWidget {
  const ChartCard({super.key, required this.title, required this.child, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.color, required this.label, this.value});

  final Color color;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        if (value != null) ...[
          const SizedBox(width: 4),
          Text(value!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ],
    );
  }
}

/// Sales, collections and expenses over time - one axis, three thin lines,
/// with a touch crosshair showing all three values.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points, this.showExpenses = true, this.height = 220});

  final List<TrendPoint> points;
  final bool showExpenses;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sales = SeriesColors.sales(context);
    final collected = SeriesColors.collected(context);
    final expenses = SeriesColors.expenses(context);

    final maxY = points.fold<double>(
        0, (m, p) => math.max(m, math.max(p.sales, math.max(p.collected, showExpenses ? p.expenses : 0))));
    final top = maxY <= 0 ? 100.0 : _niceCeil(maxY);
    final labelEvery = math.max(1, (points.length / 5).ceil());

    LineChartBarData line(List<double> ys, Color c) => LineChartBarData(
          spots: [for (var i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
          isCurved: true,
          preventCurveOverShooting: true,
          curveSmoothness: 0.2,
          color: c,
          barWidth: 2,
          dotData: FlDotData(show: points.length <= 12),
          belowBarData: BarAreaData(show: false),
        );

    final series = <(String, Color, List<double>)>[
      ('Sales', sales, points.map((p) => p.sales).toList()),
      ('Collected', collected, points.map((p) => p.collected).toList()),
      if (showExpenses) ('Expenses', expenses, points.map((p) => p.expenses).toList()),
    ];

    if (points.isEmpty) {
      return SizedBox(
          height: height,
          child: Center(child: Text('No data for this period', style: TextStyle(color: scheme.outline))));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [for (final s in series) LegendDot(color: s.$2, label: s.$1)],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: height,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble().clamp(1, double.infinity),
              minY: 0,
              maxY: top,
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: top / 4,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 46,
                    interval: top / 4,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(compactRs(v),
                          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= points.length || v != i.toDouble()) {
                        return const SizedBox.shrink();
                      }
                      final isLast = i == points.length - 1;
                      if (i % labelEvery != 0 && !isLast) return const SizedBox.shrink();
                      if (!isLast && points.length - 1 - i < labelEvery ~/ 2 + 1 && i != 0) {
                        return const SizedBox.shrink(); // keeps the last label from colliding
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(points[i].label,
                            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                handleBuiltInTouches: true,
                getTouchedSpotIndicator: (bar, idx) => idx
                    .map((_) => TouchedSpotIndicatorData(
                          FlLine(color: scheme.outline, strokeWidth: 1, dashArray: [3, 3]),
                          FlDotData(
                            getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                              radius: 4,
                              color: b.color ?? scheme.primary,
                              strokeWidth: 2,
                              strokeColor: scheme.surface,
                            ),
                          ),
                        ))
                    .toList(),
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => scheme.inverseSurface,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (var k = 0; k < spots.length; k++)
                      LineTooltipItem(
                        k == 0 ? '${points[spots[k].x.round()].label}\n' : '',
                        TextStyle(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 11),
                        children: [
                          TextSpan(
                            text: '${series[spots[k].barIndex].$1}: ${money(spots[k].y)}',
                            style: TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w500,
                                fontSize: 11.5),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              lineBarsData: [for (final s in series) line(s.$3, s.$2)],
            ),
          ),
        ),
      ],
    );
  }

  static double _niceCeil(double v) {
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    for (final m in [1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10]) {
      if (m * exp >= v) return m * exp;
    }
    return 10 * exp;
  }
}

/// Share-of-total ring with a legend that carries the numbers (so colour is never
/// the only way to read it). More than six slices fold into "Other".
class DonutChart extends StatefulWidget {
  const DonutChart({super.key, required this.items, this.centerLabel = 'Total', this.byCount = false});

  final List<NamedAmount> items;
  final String centerLabel;

  /// Size slices by count instead of rupee amount.
  final bool byCount;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  int? _touched;

  List<(String, double)> get _slices {
    final rows = widget.items
        .map((e) => (e.name, widget.byCount ? e.count.toDouble() : e.amount))
        .where((e) => e.$2 > 0)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    if (rows.length <= 6) return rows;
    final other = rows.skip(5).fold<double>(0, (s, e) => s + e.$2);
    return [...rows.take(5), ('Other', other)];
  }

  String _fmt(double v) => widget.byCount ? v.toStringAsFixed(0) : compactRs(v);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slices = _slices;
    final total = slices.fold<double>(0, (s, e) => s + e.$2);

    if (slices.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(child: Text('Nothing recorded yet', style: TextStyle(color: scheme.outline))),
      );
    }

    final focus = _touched != null && _touched! < slices.length ? slices[_touched!] : null;

    return LayoutBuilder(builder: (context, c) {
      final ring = SizedBox(
        width: 150,
        height: 150,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 46,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(
                  touchCallback: (event, res) {
                    if (!event.isInterestedForInteractions || res?.touchedSection == null) {
                      if (_touched != null) setState(() => _touched = null);
                      return;
                    }
                    final i = res!.touchedSection!.touchedSectionIndex;
                    if (i != _touched) setState(() => _touched = i < 0 ? null : i);
                  },
                ),
                sections: [
                  for (var i = 0; i < slices.length; i++)
                    PieChartSectionData(
                      value: slices[i].$2,
                      color: SeriesColors.of(context, i),
                      radius: _touched == i ? 26 : 22,
                      showTitle: false,
                    ),
                ],
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(focus?.$1 ?? widget.centerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: scheme.onSurfaceVariant)),
                Text(_fmt(focus?.$2 ?? total),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      );

      final legend = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < slices.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: SeriesColors.of(context, i),
                          borderRadius: BorderRadius.circular(3))),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(slices[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: scheme.onSurface)),
                  ),
                  Text(_fmt(slices[i].$2),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(slices[i].$2 / total * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

      if (c.maxWidth < 330) {
        return Column(children: [ring, const SizedBox(height: 12), legend]);
      }
      return Row(children: [ring, const SizedBox(width: 18), Expanded(child: legend)]);
    });
  }
}

/// Ranked horizontal bars with the value printed on each row. Rows are tappable.
class RankedBars extends StatelessWidget {
  const RankedBars({
    super.key,
    required this.rows,
    this.color,
    this.format,
    this.onTap,
    this.subtitleOf,
  });

  final List<NamedAmount> rows;
  final Color? color;
  final String Function(double)? format;
  final void Function(int index)? onTap;
  final String? Function(int index)? subtitleOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? SeriesColors.sales(context);
    final maxV = rows.fold<double>(0, (m, r) => math.max(m, r.amount));
    final fmt = format ?? compactRs;

    if (rows.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(child: Text('Nothing recorded yet', style: TextStyle(color: scheme.outline))),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap == null ? null : () => onTap!(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(rows[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Text(fmt(rows[i].amount),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      if (onTap != null)
                        Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
                    ],
                  ),
                  if (subtitleOf?.call(i) case final s?)
                    Text(s, style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        Container(height: 8, color: scheme.surfaceContainerHighest),
                        FractionallySizedBox(
                          widthFactor: maxV <= 0 ? 0 : (rows[i].amount / maxV).clamp(0.02, 1.0),
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Date-range slicer shared by the analytics screens.
enum Period { week, month, quarter, year, all }

extension PeriodX on Period {
  String get label => switch (this) {
        Period.week => '7D',
        Period.month => '30D',
        Period.quarter => '90D',
        Period.year => '12M',
        Period.all => 'All',
      };

  String get long => switch (this) {
        Period.week => 'Last 7 days',
        Period.month => 'Last 30 days',
        Period.quarter => 'Last 90 days',
        Period.year => 'Last 12 months',
        Period.all => 'All time',
      };

  DateTime? get from {
    final t = DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    return switch (this) {
      Period.week => today.subtract(const Duration(days: 6)),
      Period.month => today.subtract(const Duration(days: 29)),
      Period.quarter => today.subtract(const Duration(days: 89)),
      Period.year => DateTime(today.year - 1, today.month + 1, 1),
      Period.all => null,
    };
  }
}

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.value, required this.onChanged});

  final Period value;
  final ValueChanged<Period> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<Period>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: [
            for (final p in Period.values) ButtonSegment(value: p, label: Text(p.label)),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      );
}
