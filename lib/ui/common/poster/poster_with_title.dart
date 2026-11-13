import 'package:flutter/material.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/poster/poster_body.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// A poster tile with its title under it, and optionally a smaller [subtitle] line under that.
/// Stateless: the grid that owns the [model] rebuilds it on every data change, so the tile itself
/// watches nothing.
class PosterWithTitle extends StatelessWidget {
  final PosterModel model;
  final void Function(PosterModel)? onTap;
  final void Function(PosterModel)? onLongPress;

  /// A second line under the title (the watch history's watch date). The poster shrinks to make
  /// room for it, so the tile keeps the grid's cell size.
  final String? subtitle;

  const PosterWithTitle({required this.model, super.key, this.onTap, this.onLongPress, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: subtitle == null ? PosterConstants.aspectRationWhenTitle : PosterConstants.aspectRationWhenTitleAndSubtitle,
          child: GestureDetector(
            onTap: onTap == null ? null : () => onTap!(model),
            onLongPress: onLongPress == null ? null : () => onLongPress!(model),
            child: PosterBody(model),
          ),
        ),
        Container(
          margin: PosterConstants.titleMargin,
          child: Text(
            model.title,
            style: const TextStyle(fontSize: 12),
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (subtitle != null)
          Container(
            margin: PosterConstants.subTitleMargin,
            child: Text(
              subtitle!,
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }
}
