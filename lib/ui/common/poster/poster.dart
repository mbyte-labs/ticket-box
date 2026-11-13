import 'package:flutter/material.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/poster/poster_body.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// A poster tile without a title line. Stateless: the grid that owns the [model] rebuilds it on
/// every data change, so the tile itself watches nothing.
class Poster extends StatelessWidget {
  final PosterModel model;
  final void Function(PosterModel)? onTap;
  final void Function(PosterModel)? onLongPress;

  const Poster({required this.model, super.key, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: PosterConstants.aspectRationWhenTitle,
          child: GestureDetector(
            onTap: onTap == null ? null : () => onTap!(model),
            onLongPress: onLongPress == null ? null : () => onLongPress!(model),
            child: PosterBody(model),
          ),
        ),
      ],
    );
  }
}
