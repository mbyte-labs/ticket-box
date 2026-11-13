import 'package:flutter/material.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';
import 'package:ticketbox/ui/pages/stats/common/stats_artwork_placeholder.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// A small poster at the 2:3 poster ratio for the stats page's title rows, with the stats
/// placeholder while the image loads or when the title has none.
class StatsPosterThumb extends StatelessWidget {
  final ItemType type;

  /// Null while the title's artwork is not loaded yet.
  final ArtworkRef? poster;

  /// Width in logical (unscaled) pixels; the height follows the poster ratio.
  final double width;

  const StatsPosterThumb({required this.type, required this.poster, this.width = 40, super.key});

  @override
  Widget build(BuildContext context) {
    final poster = this.poster;
    final width = ScreenSizeUtil.calculateSize(this.width);
    final placeholder = StatsArtworkPlaceholder(type, iconSize: 20);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: width / PosterConstants.aspectRationWhenNoTitle,
        child: poster == null
            ? placeholder
            : ArtworkImage(
                ref: poster,
                fit: BoxFit.cover,
                memCacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
                placeholder: (context) => placeholder,
                errorWidget: (context) => placeholder,
              ),
      ),
    );
  }
}
