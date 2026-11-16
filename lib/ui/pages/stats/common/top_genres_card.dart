import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_period.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_meter.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The most watched genres among the tracked shows (for a year: the shows played that year), as
/// proportional bars. Genre data comes from the lazily synced show summaries, so the footnote
/// says how much of the library the numbers actually cover.
class TopGenresCard extends StatelessWidget {
  final GenreStats genres;
  final StatsPeriod period;

  const TopGenresCard(this.genres, {required this.period, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final biggest = genres.top.isEmpty ? 1 : genres.top.first.count;

    return DetailsSection(
      title: 'Top genres',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final genre in genres.top) _GenreBar(genre: genre, fraction: genre.count / biggest),
            SizedBox(height: ScreenSizeUtil.calculateSize(6)),
            Text(
              'Based on ${genres.coveredShows} of ${genres.totalShows} ${period.isAllTime ? 'tracked shows' : 'shows watched in ${period.year}'}',
              style: textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale600),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenreBar extends StatelessWidget {
  final GenreCount genre;

  /// Bar length relative to the most watched genre, 0..1.
  final double fraction;

  const _GenreBar({required this.genre, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: ScreenSizeUtil.fromLTRB(0, 4, 0, 4),
      child: Row(
        children: [
          SizedBox(
            width: ScreenSizeUtil.calculateSize(110),
            child: Text(genre.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
          ),
          SizedBox(width: ScreenSizeUtil.calculateSize(8)),
          Expanded(
            child: StatsMeter(fraction: fraction, color: ThemeColors.primary),
          ),
          SizedBox(width: ScreenSizeUtil.calculateSize(8)),
          SizedBox(
            width: ScreenSizeUtil.calculateSize(24),
            child: Text(
              '${genre.count}',
              textAlign: TextAlign.end,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
