import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_refs.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_fact_row.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_poster_thumb.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The user's movie and show ratings against TMDB's averages: how far apart they are overall, and
/// the titles where they disagree the most in each direction, each with its poster. Tapping a
/// title opens its details.
class CrowdComparisonSection extends StatelessWidget {
  final CrowdComparisonStats stats;
  final Map<MediaKey, TitleArtwork> artwork;

  const CrowdComparisonSection(this.stats, {required this.artwork, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final delta = stats.delta;

    return DetailsSection(
      title: 'You vs the crowd',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _signed(delta),
                  style: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: _gapColor(delta)),
                ),
                SizedBox(width: ScreenSizeUtil.calculateSize(12)),
                Expanded(child: Text(_verdictLabel(stats.verdict), style: textTheme.titleSmall)),
              ],
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(8)),
            StatsFactRow(label: 'Your average', value: _average(stats.userAverage)),
            StatsFactRow(label: 'TMDB average', value: _average(stats.crowdAverage)),
            StatsFactRow(label: 'Compared', value: '${stats.compared} of ${stats.totalRated} rated titles'),
            if (stats.lovedMore.isNotEmpty) ...[
              _listHeader(context, "You loved, the crowd didn't"),
              for (final gap in stats.lovedMore) _GapRow(gap, poster: _poster(gap)),
            ],
            if (stats.lovedLess.isNotEmpty) ...[
              _listHeader(context, "The crowd loved, you didn't"),
              for (final gap in stats.lovedLess) _GapRow(gap, poster: _poster(gap)),
            ],
          ],
        ),
      ),
    );
  }

  ArtworkRef? _poster(CrowdGap gap) => artwork.posterOf(MediaKey(type: gap.type, tmdbId: gap.tmdbId));

  // A method rather than a widget: a const widget reading ScreenSizeUtil would keep stale sizes.
  static Widget _listHeader(BuildContext context, String title) {
    return Padding(
      padding: ScreenSizeUtil.fromLTRB(0, 14, 0, 4),
      child: Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
    );
  }

  static String _verdictLabel(CrowdVerdict verdict) {
    return switch (verdict) {
      CrowdVerdict.harsher => 'Tougher critic than the crowd',
      CrowdVerdict.kinder => 'Easier to please than the crowd',
      CrowdVerdict.inSync => 'In tune with the crowd',
    };
  }
}

class _GapRow extends StatelessWidget {
  final CrowdGap gap;
  final ArtworkRef? poster;

  const _GapRow(this.gap, {required this.poster});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fallback = gap.type == ItemType.movie ? 'A movie' : 'A show';
    final title = gap.title.isEmpty ? fallback : (gap.year == null ? gap.title : '${gap.title} (${gap.year})');

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (gap.type == ItemType.movie) {
          PosterNavigation.movieNavigateRaw(context, gap.tmdbId);
        } else {
          PosterNavigation.showNavigateRaw(context, gap.tmdbId);
        }
      },
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(0, 6, 0, 6),
        child: Row(
          children: [
            StatsPosterThumb(type: gap.type, poster: poster),
            SizedBox(width: ScreenSizeUtil.calculateSize(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: textTheme.bodyMedium),
                  Text(
                    'You ${gap.userRating} · TMDB ${_average(gap.crowdRating)}',
                    style: textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500),
                  ),
                ],
              ),
            ),
            SizedBox(width: ScreenSizeUtil.calculateSize(8)),
            Text(
              _signed(gap.gap),
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: _gapColor(gap.gap)),
            ),
          ],
        ),
      ),
    );
  }
}

String _average(double average) => average.toStringAsFixed(1);

String _signed(double delta) {
  final rounded = _average(delta.abs());
  if (rounded == '0.0') return '±0.0';
  return delta < 0 ? '−$rounded' : '+$rounded';
}

Color? _gapColor(double delta) {
  if (_average(delta.abs()) == '0.0') return null;
  return delta < 0 ? ThemeColors.error : ThemeColors.success;
}
