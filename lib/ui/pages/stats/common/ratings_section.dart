import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_bar_chart.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_fact_row.dart';

/// The 1..10 distribution of the ratings the user has given, plus the averages computed from
/// the locally stored ratings.
class RatingsSection extends StatelessWidget {
  /// Votes for ratings 1..10 over the locally stored ratings, null when nothing was rated.
  final List<int>? distribution;

  /// Null when the user has rated nothing.
  final RatingsGivenStats? ratingsGiven;

  const RatingsSection({required this.distribution, required this.ratingsGiven, super.key});

  @override
  Widget build(BuildContext context) {
    final votes = distribution;
    final given = ratingsGiven;

    return DetailsSection(
      title: 'Your ratings',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (votes != null && votes.any((count) => count > 0)) ...[
              StatsBarChart(
                values: votes.map((count) => count.toDouble()).toList(),
                xLabel: (index) => '${index + 1}',
                tooltipText: (index) => '${votes[index]} rated ${index + 1}',
              ),
              SizedBox(height: ScreenSizeUtil.calculateSize(10)),
            ],
            if (given != null) ...[
              StatsFactRow(label: 'Ratings given', value: '${given.total}'),
              StatsFactRow(label: 'Average rating', value: given.average.toStringAsFixed(1)),
              if (given.movieAverage != null) StatsFactRow(label: 'Movies average', value: given.movieAverage!.toStringAsFixed(1)),
              if (given.showAverage != null) StatsFactRow(label: 'Shows average', value: given.showAverage!.toStringAsFixed(1)),
              if (given.episodeAverage != null) StatsFactRow(label: 'Episodes average', value: given.episodeAverage!.toStringAsFixed(1)),
            ],
          ],
        ),
      ),
    );
  }
}
