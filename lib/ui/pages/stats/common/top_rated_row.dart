import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/common/poster/poster_with_title.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';

/// The user's best rated movies and shows as a horizontal row of poster tiles, best first, each
/// opening its details page. The same layout as the details pages' "Similar" rows.
///
/// Each tile is a [PosterWithTitle] over a [PosterModel] the bloc built from the catalogue row
/// and stamped with the user's marks (the heart pill with the rating), so this only lays them
/// out and handles the tap.
///
/// Hidden entirely while the tiles are not built yet or when nothing is rated.
class TopRatedRow extends StatelessWidget {
  /// Tile width; the row height below is derived from it.
  static const _itemWidth = 110.0;

  /// [PosterWithTitle] is an `AspectRatio(2/2.8)` plus a title line whose `fontSize` is a fixed
  /// 12 and so does not shrink with the screen - small phones need proportionally more room for
  /// it. Same slack as the details pages' similar rows.
  static const _rowHeight = _itemWidth * 3.3 / 2;

  final List<PosterModel> models;

  const TopRatedRow({required this.models, super.key});

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return const SizedBox.shrink();
    }

    return DetailsSection(
      title: 'Your highest rated',
      child: SizedBox(
        height: ScreenSizeUtil.calculateSize(_rowHeight),
        width: double.infinity,
        // Viewport-lazy, so only the visible tiles mount and decode their artwork.
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: models.length,
          itemBuilder: (context, index) {
            final model = models[index];

            return Padding(
              padding: ScreenSizeUtil.fromLTRB(0, 0, 8, 0),
              child: SizedBox(
                width: ScreenSizeUtil.calculateSize(_itemWidth),
                // Keyed by the model's grid id, so a reorder re-parents the existing elements
                // instead of rebuilding them.
                child: PosterWithTitle(key: Key('${model.id}'), model: model, onTap: (model) => PosterNavigation.navigate(context, model)),
              ),
            );
          },
        ),
      ),
    );
  }
}
