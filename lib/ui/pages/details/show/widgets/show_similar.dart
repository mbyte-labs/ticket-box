import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/poster/poster_with_title.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';

/// Similar shows section: a horizontal row of poster tiles, each opening that show's details
/// page. The show-side twin of the movie page's similar row.
///
/// Each tile is a [PosterWithTitle] over a model the bloc built from the snapshot's related list
/// and marked with the user's rows — this only lays them out and handles the tap.
///
/// Hidden entirely when there is nothing to show. Unlike the cast section there is no
/// placeholder: that a show has no related entries on TMDB is not something the user needs
/// told, and an empty row at the bottom of the page reads as a rendering fault.
class ShowSimilar extends StatelessWidget {
  /// Tile width; the row height below is derived from it.
  static const _itemWidth = 110.0;

  /// [PosterWithTitle] is an `AspectRatio(2/2.8)` plus a title line whose `fontSize` is a fixed
  /// 12 and so does not shrink with the screen — small phones need proportionally more room for
  /// it. The same slack the seasons grid builds into its aspect ratio, expressed as a height:
  /// unused space just leaves a gap, whereas too little overflows the tile's Column.
  static const _rowHeight = _itemWidth * 3.3 / 2;

  final List<PosterModel> models;

  const ShowSimilar({required this.models, super.key});

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return const SizedBox.shrink();
    }

    return DetailsSection(
      title: 'Similar shows',
      child: SizedBox(
        height: ScreenSizeUtil.calculateSize(_rowHeight),
        width: double.infinity,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: models.length,
          itemBuilder: (context, index) {
            final model = models[index];

            return Padding(
              padding: ScreenSizeUtil.fromLTRB(0, 0, 8, 0),
              child: SizedBox(
                width: ScreenSizeUtil.calculateSize(_itemWidth),
                child: PosterWithTitle(key: Key('${model.id}'), model: model, onTap: (model) => PosterNavigation.navigate(context, model)),
              ),
            );
          },
        ),
      ),
    );
  }
}
