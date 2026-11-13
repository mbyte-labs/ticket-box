import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_period.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_bar_chart.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_fact_row.dart';

/// The average movie and show rating per month over the last year (or the selected one), and
/// whether the recent ratings run harsher or kinder than the earlier ones. In a past year
/// "recent" is the year's last [RatingTrendStats.windowDays] days.
class RatingTrendSection extends StatelessWidget {
  final RatingTrendStats trend;
  final StatsPeriod period;

  const RatingTrendSection(this.trend, {required this.period, super.key});

  @override
  Widget build(BuildContext context) {
    final monthly = trend.monthly;
    final delta = trend.delta;
    final verdict = trend.trend;
    final year = period.year;
    final recentLabel = period.isPast(DateTime.now())
        ? 'Last ${RatingTrendStats.windowDays} days of $year'
        : 'Last ${RatingTrendStats.windowDays} days';

    return DetailsSection(
      title: 'Ratings over time',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Average rating per month (movies & shows)', style: Theme.of(context).textTheme.bodySmall),
            SizedBox(height: ScreenSizeUtil.calculateSize(8)),
            StatsBarChart(
              // A fixed 0-10 scale: auto-scaling would make 7.1 vs 7.4 look dramatic.
              maxY: 10,
              values: monthly.map((month) => month.average ?? 0).toList(),
              // Every other month, so the labels never collide on narrow screens.
              xLabel: (index) => index.isOdd ? '' : _monthLabel(monthly[index]),
              tooltipText: (index) => '${_monthLabel(monthly[index])} ${monthly[index].year}\n${_monthSummary(monthly[index])}',
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(10)),
            if (trend.recentAverage != null)
              StatsFactRow(label: recentLabel, value: '${_average(trend.recentAverage!)} avg (${trend.recentCount})'),
            if (trend.earlierAverage != null)
              StatsFactRow(label: 'Before that', value: '${_average(trend.earlierAverage!)} avg (${trend.earlierCount})'),
            if (delta != null && verdict != null) StatsFactRow(label: _verdictLabel(verdict), value: _signed(delta)),
          ],
        ),
      ),
    );
  }

  static String _monthLabel(MonthlyRating month) => DateFormat.MMM().format(DateTime(month.year, month.month));

  static String _monthSummary(MonthlyRating month) {
    if (month.average == null) {
      return 'No ratings';
    }
    return '${_average(month.average!)} avg · ${month.count == 1 ? '1 rating' : '${month.count} ratings'}';
  }

  static String _average(double average) => average.toStringAsFixed(1);

  static String _signed(double delta) {
    final rounded = _average(delta.abs());
    if (rounded == '0.0') return '±0.0';
    return delta < 0 ? '−$rounded' : '+$rounded';
  }

  static String _verdictLabel(RatingTrend trend) {
    return switch (trend) {
      RatingTrend.harsher => 'Rating more harshly lately',
      RatingTrend.kinder => 'Rating more generously lately',
      RatingTrend.steady => 'Rating consistently',
    };
  }
}
