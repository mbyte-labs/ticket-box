import 'package:flutter/material.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/service/stats/stats_period.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The headline 2x2 grid: hours watched, movies, episodes and total plays, followed by the
/// movies vs TV split of the watched time. Titled after the period the numbers cover.
class StatTileGrid extends StatelessWidget {
  final HeadlineStats headline;
  final StatsPeriod period;

  const StatTileGrid(this.headline, {required this.period, super.key});

  @override
  Widget build(BuildContext context) {
    final tvShare = headline.tvShare;

    return DetailsSection(
      title: period.label,
      child: DetailsCard(
        child: Column(
          children: [
            Row(
              children: [
                // Summed from the runtimes cached with the movie and episode summaries; a play whose
                // runtime is not cached yet counts as zero, so the number can only grow.
                _StatCell(value: _compactFormat(headline.hoursWatched), label: 'Hours watched'),
                _StatCell(value: _compactFormat(headline.totalPlays), label: 'Total plays'),
              ],
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(14)),
            Row(
              children: [
                _StatCell(value: _compactFormat(headline.moviesWatched), label: 'Movies'),
                _StatCell(value: _compactFormat(headline.episodesWatched), label: 'Episodes'),
              ],
            ),
            // Hidden until at least one play has a cached runtime: there is no time to split yet.
            if (tvShare != null) ...[
              SizedBox(height: ScreenSizeUtil.calculateSize(16)),
              _TimeSplit(tvShare: tvShare, movieMinutes: headline.movieMinutes, episodeMinutes: headline.episodeMinutes),
            ],
          ],
        ),
      ),
    );
  }

  static String _compactFormat(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 10000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toString();
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;

  const _StatCell({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500)),
        ],
      ),
    );
  }
}

/// Movies vs TV share of the watched time: the dominant side as a sentence, a two-tone bar and a
/// legend with the hours behind each side.
class _TimeSplit extends StatelessWidget {
  static const _tvColor = ThemeColors.primary;
  static const _movieColor = ThemeColors.secondary;

  final double tvShare;
  final int movieMinutes;
  final int episodeMinutes;

  const _TimeSplit({required this.tvShare, required this.movieMinutes, required this.episodeMinutes});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // A tie goes to TV.
    final headlineText = tvShare >= 0.5 ? '${_percent(tvShare)} of your time is TV' : '${_percent(1 - tvShare)} of your time is movies';
    final barHeight = ScreenSizeUtil.calculateSize(8);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(headlineText, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        SizedBox(height: ScreenSizeUtil.calculateSize(8)),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: barHeight,
            // Stretched: a childless ColoredBox takes the smallest size it is allowed, which a
            // Row's loose cross axis would make zero.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (episodeMinutes > 0)
                  Expanded(
                    flex: episodeMinutes,
                    child: const ColoredBox(color: _tvColor),
                  ),
                if (movieMinutes > 0)
                  Expanded(
                    flex: movieMinutes,
                    child: const ColoredBox(color: _movieColor),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: ScreenSizeUtil.calculateSize(6)),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _LegendEntry(color: _tvColor, text: 'TV · ${StatTileGrid._compactFormat(episodeMinutes ~/ 60)}h'),
            _LegendEntry(color: _movieColor, text: 'Movies · ${StatTileGrid._compactFormat(movieMinutes ~/ 60)}h'),
          ],
        ),
      ],
    );
  }

  /// Whole percent, except that a side which is there but rounds away never reads as 0% or 100%.
  static String _percent(double share) {
    final percent = (share * 100).round();
    if (percent == 100 && share < 1) return '>99%';
    if (percent == 0 && share > 0) return '<1%';
    return '$percent%';
  }
}

class _LegendEntry extends StatelessWidget {
  final Color color;
  final String text;

  const _LegendEntry({required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    final dotSize = ScreenSizeUtil.calculateSize(8);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: dotSize,
          height: dotSize,
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        SizedBox(width: ScreenSizeUtil.calculateSize(6)),
        Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500)),
      ],
    );
  }
}
