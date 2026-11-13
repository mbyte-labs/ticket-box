import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';

/// TMDB community figures for a movie or show — the popularity score and the vote count —
/// rendered as a single [DetailsCard] of equal-width tiles.
///
/// Replaces the old five-tile "Community" card. TMDB exposes only these two numbers at
/// the title level, and both arrive with the summary, so the card either shows them or is not
/// there at all: it collapses to nothing while both are still null.
class DetailsPopularityCard extends StatelessWidget {
  /// TMDB `popularity` — an unbounded, relative score that TMDB recomputes daily.
  final double? popularity;

  /// TMDB `vote_count` behind the title's average score.
  final int? voteCount;

  const DetailsPopularityCard({required this.popularity, required this.voteCount, super.key});

  @override
  Widget build(BuildContext context) {
    final score = popularity;
    final votes = voteCount;
    if (score == null && votes == null) {
      return const SizedBox.shrink();
    }

    return DetailsSection(
      title: 'On TMDB',
      child: DetailsCard(
        padding: ScreenSizeUtil.fromLTRB(4, 12, 4, 12),
        child: Row(
          children: [
            if (score != null) _StatTile(label: 'popularity', value: _formatPopularity(score)),
            if (votes != null) _StatTile(label: 'votes', value: NumberFormat.compact().format(votes)),
          ],
        ),
      ),
    );
  }

  /// One decimal while the score is small enough for the decimal to carry meaning ("42.7");
  /// compact once it crosses a thousand ("1.2K"), where the fraction is noise.
  static String _formatPopularity(double score) {
    return score >= 1000 ? NumberFormat.compact().format(score) : score.toStringAsFixed(1);
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;

  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          SizedBox(height: ScreenSizeUtil.calculateSize(2)),
          Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
