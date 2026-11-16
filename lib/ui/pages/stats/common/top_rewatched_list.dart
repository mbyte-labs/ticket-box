import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/service/stats/stats_models.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_refs.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_poster_thumb.dart';
import 'package:ticketbox/ui/theme/theme_colors.dart';

/// The items watched more than once, most plays first, each with its poster. Tapping a row
/// opens its details page.
class TopRewatchedList extends StatelessWidget {
  final List<TopRewatchedItem> items;
  final Map<MediaKey, TitleArtwork> artwork;

  const TopRewatchedList(this.items, {required this.artwork, super.key});

  @override
  Widget build(BuildContext context) {
    return DetailsSection(
      title: 'Most rewatched',
      child: DetailsCard(
        padding: ScreenSizeUtil.fromLTRB(4, 4, 4, 4),
        child: Column(
          children: [
            for (var index = 0; index < items.length; index++)
              _RewatchedRow(
                rank: index + 1,
                item: items[index],
                poster: artwork.posterOf(MediaKey(type: items[index].type, tmdbId: items[index].tmdbId)),
              ),
          ],
        ),
      ),
    );
  }
}

class _RewatchedRow extends StatelessWidget {
  final int rank;
  final TopRewatchedItem item;
  final ArtworkRef? poster;

  const _RewatchedRow({required this.rank, required this.item, required this.poster});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (item.type == ItemType.movie) {
          PosterNavigation.movieNavigateRaw(context, item.tmdbId);
        } else {
          PosterNavigation.showNavigateRaw(context, item.tmdbId);
        }
      },
      child: Padding(
        padding: ScreenSizeUtil.fromLTRB(10, 6, 10, 6),
        child: Row(
          children: [
            SizedBox(
              width: ScreenSizeUtil.calculateSize(24),
              child: Text(
                '$rank',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: ThemeColors.greyScale500),
              ),
            ),
            SizedBox(width: ScreenSizeUtil.calculateSize(6)),
            StatsPosterThumb(type: item.type, poster: poster),
            SizedBox(width: ScreenSizeUtil.calculateSize(12)),
            Expanded(
              child: Text(
                item.title.isEmpty ? (item.type == ItemType.movie ? 'A movie' : 'A show') : item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium,
              ),
            ),
            SizedBox(width: ScreenSizeUtil.calculateSize(8)),
            Text(
              '${item.plays}×',
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: ThemeColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
