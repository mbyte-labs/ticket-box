import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Single-series bar chart shared by the stats sections: brand-colored bars with rounded tops,
/// hairline horizontal grid only, muted axis text and a touch tooltip. There is deliberately no
/// legend - the section header names the one series.
class StatsBarChart extends StatelessWidget {
  final List<double> values;

  /// The x-axis label of one bar. Return an empty string to skip a label (used to thin out the
  /// month labels so they never collide on narrow screens).
  final String Function(int index) xLabel;

  /// The tooltip text shown while a bar is touched.
  final String Function(int index) tooltipText;

  /// Chart height in logical (unscaled) pixels.
  final double height;

  /// A fixed top of the y axis, for values on a known scale (average ratings out of 10). Null
  /// scales to the tallest bar.
  final double? maxY;

  const StatsBarChart({required this.values, required this.xLabel, required this.tooltipText, this.height = 150, this.maxY, super.key});

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500);
    final tallest = values.fold(0.0, (max, value) => value > max ? value : max);
    final maxValue = maxY ?? tallest;

    return SizedBox(
      height: ScreenSizeUtil.calculateSize(height),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          // Headroom above the tallest bar; 1 keeps an all-zero chart from collapsing.
          maxY: maxY ?? (maxValue == 0 ? 1 : maxValue * 1.15),
          barGroups: [
            for (var index = 0; index < values.length; index++)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: values[index],
                    color: ThemeColors.primary,
                    width: ScreenSizeUtil.calculateSize(14),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => const FlLine(color: ThemeColors.dark4, strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: ScreenSizeUtil.calculateSize(40),
                getTitlesWidget: (value, meta) {
                  // Only whole numbers - a play count axis with fractional ticks reads wrong.
                  if (value % 1 != 0 || value > maxValue) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(meta.formattedValue, style: labelStyle),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: ScreenSizeUtil.calculateSize(26),
                getTitlesWidget: (value, meta) {
                  final label = xLabel(value.toInt());
                  if (label.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 4,
                    child: Text(label, style: labelStyle),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => ThemeColors.dark3,
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(tooltipText(group.x), const TextStyle(color: ThemeColors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}
