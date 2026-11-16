import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_refs.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_banner_card.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_bar_chart.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_fact_row.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The release decades of the titles watched, plus the oldest and the newest of them shown as
/// backdrop banners.
class DecadesSection extends StatelessWidget {
  /// More bars than this and only every other one gets an x-axis label.
  static const _maxLabelledBars = 8;

  final DecadeStats stats;
  final Map<MediaKey, TitleArtwork> artwork;

  const DecadesSection(this.stats, {required this.artwork, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final decades = stats.decades;
    final favorite = stats.favorite;
    // '20s would be ambiguous once the chart spans a century, so long spans use full years.
    final shortLabels = decades.length < 10;
    final thinLabels = decades.length > _maxLabelledBars;

    return DetailsSection(
      title: 'Decades',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Titles watched by release decade', style: textTheme.bodySmall),
            SizedBox(height: ScreenSizeUtil.calculateSize(8)),
            StatsBarChart(
              values: decades.map((decade) => decade.titles.toDouble()).toList(),
              xLabel: (index) {
                if (thinLabels && index.isOdd) return '';
                final decade = decades[index].decade;
                return shortLabels ? "'${(decade % 100).toString().padLeft(2, '0')}s" : '$decade';
              },
              tooltipText: (index) => '${decades[index].decade}s\n${_titles(decades[index].titles)}',
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(10)),
            StatsFactRow(label: 'Favorite decade', value: '${favorite.decade}s · ${(stats.share(favorite) * 100).round()}%'),
            SizedBox(height: ScreenSizeUtil.calculateSize(12)),
            _EraBanners(stats: stats, artwork: artwork),
            if (stats.coveredTitles < stats.totalTitles) ...[
              SizedBox(height: ScreenSizeUtil.calculateSize(10)),
              Text(
                'Based on ${stats.coveredTitles} of ${stats.totalTitles} watched titles',
                style: textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _titles(int count) => count == 1 ? '1 title' : '$count titles';
}

/// The oldest and newest banners: side by side when there is room for two wide banners
/// (tablets, landscape), stacked and a little flatter on phones so they don't eat the screen.
class _EraBanners extends StatelessWidget {
  /// Below this card width two side-by-side banners get too small to read.
  static const _sideBySideMinWidth = 560.0;

  final DecadeStats stats;
  final Map<MediaKey, TitleArtwork> artwork;

  const _EraBanners({required this.stats, required this.artwork});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = !stats.singleTitle && constraints.maxWidth >= _sideBySideMinWidth;
        final aspectRatio = sideBySide ? 16 / 9 : 2.0;
        final gap = ScreenSizeUtil.calculateSize(10);
        final oldest = _banner('Oldest', stats.oldest, aspectRatio);

        if (stats.singleTitle) {
          return oldest;
        }

        final newest = _banner('Newest', stats.newest, aspectRatio);
        if (sideBySide) {
          return Row(
            children: [
              Expanded(child: oldest),
              SizedBox(width: gap),
              Expanded(child: newest),
            ],
          );
        }
        return Column(
          children: [
            oldest,
            SizedBox(height: gap),
            newest,
          ],
        );
      },
    );
  }

  Widget _banner(String label, EraTitle title, double aspectRatio) {
    final key = MediaKey(type: title.type, tmdbId: title.tmdbId);
    return StatsBannerCard(
      mediaKey: key,
      banner: artwork.bannerOf(key),
      badge: '${label.toUpperCase()} · ${title.year}',
      title: title.title,
      aspectRatio: aspectRatio,
    );
  }
}
