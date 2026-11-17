import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/poster/poster_with_title.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';

/// Season navigation grid: one poster tile per season, opening its details page.
///
/// Each tile is a [PosterWithTitle] over a model the bloc built from the season rows (or the
/// snapshot's season stubs) and marked with the user's rows — this only lays them out and
/// handles the tap.
///
/// Exposed as slivers rather than as a widget: a [SliverGrid] stays viewport-lazy inside
/// the page's `CustomScrollView`, so only the visible rows ever mount.
class ShowSeasonsGrid {
  const ShowSeasonsGrid._();

  /// Fixed rather than max-extent based: `SliverGridDelegateWithMaxCrossAxisExtent`
  /// derives its count with a ceiling, so the layout would silently flip between 3 and 4
  /// columns across phone widths. Pinning the count keeps every phone at 3-up and lets the
  /// cell width scale with the screen instead.
  static const _crossAxisCount = 3;

  /// [PosterWithTitle] is an `AspectRatio(2/2.8)` plus a title line whose `fontSize` is a
  /// fixed 12 and so does not shrink with the screen — small phones need proportionally
  /// more room for it. The slack here covers a ~320px-wide phone; unused space just leaves
  /// a gap, whereas too little overflows the tile's Column.
  static const _childAspectRatio = 2 / 3.3;

  static List<Widget> slivers(List<PosterModel> models) {
    if (models.isEmpty) {
      return const [];
    }

    return [
      // Same gutter DetailsSection applies, so the header lines up with the sections
      // above and below it.
      SliverToBoxAdapter(
        child: Padding(padding: ScreenSizeUtil.fromLTRB(12, 18, 12, 0), child: const DetailsSectionHeader('Seasons')),
      ),
      SliverPadding(
        padding: ScreenSizeUtil.fromLTRB(12, 0, 12, 0),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _crossAxisCount,
            childAspectRatio: _childAspectRatio,
            crossAxisSpacing: ScreenSizeUtil.calculateSize(8),
            mainAxisSpacing: ScreenSizeUtil.calculateSize(8),
          ),
          delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
            final model = models[index];
            return PosterWithTitle(key: Key('${model.id}'), model: model, onTap: (model) => PosterNavigation.navigate(context, model));
          }, childCount: models.length),
        ),
      ),
    ];
  }
}
