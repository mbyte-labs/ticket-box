import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_period.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/plays_heatmap.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_refs.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_bar_chart.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_fact_row.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_poster_thumb.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Plays per month and per day over the last year (or the selected one), plays per weekday and
/// per part of the day, plus the habit facts derived from the history: when the user usually
/// watches, streaks, how long the account has been tracking (the active days, for a year) and
/// the very first title watched. A past year has no "current" facts, so its current streak is
/// left out.
class ActivitySection extends StatelessWidget {
  /// The two habit charts are secondary to the monthly one, so they are shorter.
  static const _habitChartHeight = 110.0;

  final WatchActivityStats activity;
  final StatsPeriod period;
  final Map<MediaKey, TitleArtwork> artwork;

  const ActivitySection(this.activity, {required this.period, required this.artwork, super.key});

  @override
  Widget build(BuildContext context) {
    final monthly = activity.monthly;
    final weekdays = activity.weekdayPlays;
    final timeOfDay = activity.timeOfDay;
    final captionStyle = Theme.of(context).textTheme.bodySmall;
    final firstPlay = activity.firstPlay;
    final year = period.year;
    final isPast = period.isPast(DateTime.now());

    return DetailsSection(
      title: 'Watch activity',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(year == null ? 'Plays over the last 12 months' : 'Plays per month in $year', style: captionStyle),
            SizedBox(height: ScreenSizeUtil.calculateSize(8)),
            StatsBarChart(
              values: monthly.map((month) => month.plays.toDouble()).toList(),
              // Every other month, so the labels never collide on narrow screens.
              xLabel: (index) => index.isOdd ? '' : _monthLabel(monthly[index]),
              tooltipText: (index) => '${_monthLabel(monthly[index])} ${monthly[index].year}\n${_plays(monthly[index].plays)}',
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(16)),
            Text(year == null ? 'Plays over the last year' : 'Plays per day in $year', style: captionStyle),
            SizedBox(height: ScreenSizeUtil.calculateSize(8)),
            PlaysHeatmap(activity.daily),
            if (weekdays.any((count) => count > 0)) ...[
              SizedBox(height: ScreenSizeUtil.calculateSize(16)),
              Text('Plays by weekday', style: captionStyle),
              SizedBox(height: ScreenSizeUtil.calculateSize(8)),
              StatsBarChart(
                height: _habitChartHeight,
                values: weekdays.map((count) => count.toDouble()).toList(),
                xLabel: (index) => DateFormat.E().format(_weekday(index)),
                tooltipText: (index) => '${DateFormat.EEEE().format(_weekday(index))}\n${_plays(weekdays[index])}',
              ),
            ],
            if (timeOfDay != null) ...[
              SizedBox(height: ScreenSizeUtil.calculateSize(16)),
              Text('Plays by time of day', style: captionStyle),
              SizedBox(height: ScreenSizeUtil.calculateSize(8)),
              StatsBarChart(
                height: _habitChartHeight,
                values: timeOfDay.plays.map((count) => count.toDouble()).toList(),
                xLabel: (index) => DayPart.values[index].label,
                tooltipText: (index) {
                  final part = DayPart.values[index];
                  return '${part.label} (${part.hours})\n${_plays(timeOfDay.plays[index])}\n${_percent(timeOfDay.share(part))}';
                },
              ),
            ],
            SizedBox(height: ScreenSizeUtil.calculateSize(10)),
            if (timeOfDay != null)
              StatsFactRow(
                label: timeOfDay.dominant.persona,
                value: '${_percent(timeOfDay.share(timeOfDay.dominant))} ${timeOfDay.dominant.rangeText}',
              ),
            StatsFactRow(label: 'Longest streak', value: _days(activity.longestStreakDays)),
            if (!isPast) StatsFactRow(label: 'Current streak', value: _days(activity.currentStreakDays)),
            if (year == null && activity.firstWatch != null) StatsFactRow(label: 'Tracking for', value: _days(activity.daysTracked)),
            if (year != null) StatsFactRow(label: 'Active days', value: _days(activity.daily.activeDays)),
            if (firstPlay != null) ...[
              Padding(
                padding: ScreenSizeUtil.fromLTRB(0, 14, 0, 4),
                child: Text(
                  year == null ? 'Where it all started' : 'First play of $year',
                  style: captionStyle?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _FirstPlayRow(firstPlay, poster: artwork.posterOf(firstPlay.key.showKey)),
            ],
          ],
        ),
      ),
    );
  }

  static String _monthLabel(MonthlyPlays month) => DateFormat.MMM().format(DateTime(month.year, month.month));

  /// A date falling on weekday [index] (0 = Monday), for formatting its name: 2024-01-01 was a
  /// Monday.
  static DateTime _weekday(int index) => DateTime(2024, 1, 1 + index);

  static String _plays(int plays) => plays == 1 ? '1 play' : '$plays plays';

  static String _percent(double share) => '${(share * 100).round()}%';

  static String _days(int days) => days == 1 ? '1 day' : '$days days';
}

/// The oldest play on record: its poster, the movie's or show's title and, for an episode, which
/// one, with the date. Tapping opens the title.
class _FirstPlayRow extends StatelessWidget {
  final FirstPlay play;
  final ArtworkRef? poster;

  const _FirstPlayRow(this.play, {required this.poster});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final key = play.key.showKey;
    final episodeLabel = play.episodeLabel;
    final date = DateFormat.yMMMd().format(play.watchedAt.toLocal());

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (key.type == ItemType.movie) {
          PosterNavigation.movieNavigateRaw(context, key.tmdbId);
        } else {
          PosterNavigation.showNavigateRaw(context, key.tmdbId);
        }
      },
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(0, 6, 0, 6),
        child: Row(
          children: [
            StatsPosterThumb(type: key.type, poster: poster),
            SizedBox(width: ScreenSizeUtil.calculateSize(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    play.title.isEmpty ? (key.type == ItemType.movie ? 'A movie' : 'A show') : play.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                  Text(
                    episodeLabel == null ? date : '$episodeLabel · $date',
                    style: textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500),
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
