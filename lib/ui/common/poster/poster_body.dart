import 'package:flutter/material.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/poster/poster_item_background.dart';
import 'package:ticketbox/ui/common/poster/poster_pills_bottom_right.dart';
import 'package:ticketbox/ui/common/poster/poster_pills_top_left.dart';
import 'package:ticketbox/ui/common/poster/poster_pills_top_right.dart';

/// The artwork and every pill of one tile; the shape around it is the caller's.
class PosterBody extends StatelessWidget {
  final PosterModel model;

  /// The image to draw instead of the model's poster: an episode still.
  final ArtworkRef? artwork;

  const PosterBody(this.model, {super.key, this.artwork});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        PosterItemBackground(model, artwork: artwork),
        PosterTopLeftPills(model),
        PosterTopRightPills(model),
        PosterBottomRightPills(model),
      ],
    );
  }
}
