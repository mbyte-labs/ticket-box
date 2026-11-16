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
import 'package:ticketbox/ui/pages/stats/common/stats_meter.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_poster_thumb.dart';
import 'package:ticketbox/ui/theme/action_colors.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// Tracked / completed / in-progress counts, the mean per-show completion as a meter, and the
/// in-progress shows closest to their last aired episode, each with its poster and its own
/// meter. The meters wear the mark-as-watched violet (the details page's watch-progress
/// precedent) rather than the theme's loading pink: this is watched data, not loading.
class CompletionCard extends StatelessWidget {
  final ShowCompletionStats completion;
  final Map<MediaKey, TitleArtwork> artwork;

  const CompletionCard(this.completion, {required this.artwork, super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final meterColor = context.actionColors.markWatchedAccent;
    final percent = (completion.averageCompletion * 100).round();

    return DetailsSection(
      title: 'Show completion',
      child: DetailsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Average completion', style: textTheme.bodyMedium?.copyWith(color: ThemeColors.greyScale500)),
                Text(
                  '$percent%',
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: meterColor),
                ),
              ],
            ),
            SizedBox(height: ScreenSizeUtil.calculateSize(8)),
            StatsMeter(fraction: completion.averageCompletion, color: meterColor),
            SizedBox(height: ScreenSizeUtil.calculateSize(10)),
            StatsFactRow(label: 'Shows tracked', value: '${completion.tracked}'),
            StatsFactRow(label: 'Completed', value: '${completion.completed}'),
            StatsFactRow(label: 'In progress', value: '${completion.inProgress}'),
            if (completion.almostThere.isNotEmpty) ...[
              Padding(
                padding: ScreenSizeUtil.fromLTRB(0, 14, 0, 4),
                child: Text('Almost there', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
              for (final show in completion.almostThere)
                _AlmostThereRow(show, poster: artwork.posterOf(MediaKey.show(show.tmdbId)), meterColor: meterColor),
            ],
          ],
        ),
      ),
    );
  }
}

/// One nearly finished show: poster, title, how many episodes are left and its meter. Tapping
/// opens the show.
class _AlmostThereRow extends StatelessWidget {
  final AlmostThereShow show;
  final ArtworkRef? poster;
  final Color meterColor;

  const _AlmostThereRow(this.show, {required this.poster, required this.meterColor});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final left = show.left;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => PosterNavigation.showNavigateRaw(context, show.tmdbId),
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(0, 6, 0, 6),
        child: Row(
          children: [
            StatsPosterThumb(type: ItemType.show, poster: poster),
            SizedBox(width: ScreenSizeUtil.calculateSize(12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    show.title.isEmpty ? 'A show' : show.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                  Text(
                    '${left == 1 ? '1 episode' : '$left episodes'} left · ${show.completed} of ${show.aired} watched',
                    style: textTheme.bodySmall?.copyWith(color: ThemeColors.greyScale500),
                  ),
                  SizedBox(height: ScreenSizeUtil.calculateSize(6)),
                  StatsMeter(fraction: show.completion, color: meterColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
