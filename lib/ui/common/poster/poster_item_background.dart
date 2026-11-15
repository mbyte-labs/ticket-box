import 'package:flutter/material.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// The artwork of one tile: the local file for a tracked title, the browse cache for an
/// untracked one, the no-image title card when TMDB has nothing.
class PosterItemBackground extends StatelessWidget {
  final PosterModel model;

  /// Image to render instead of the model's poster. Used by [StillWithTitle], whose artwork is
  /// the episode still rather than the season poster an episode tile shows otherwise.
  final ArtworkRef? artwork;

  const PosterItemBackground(this.model, {super.key, this.artwork});

  @override
  Widget build(BuildContext context) {
    final ref = artwork ?? ArtworkRef.fromPosterKey(model.key, model.posterPath);
    if (ref.tmdbPath == null) {
      return _NoPosterCard(model.noPosterText);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return ArtworkImage(
          ref: ref,
          fit: BoxFit.fitWidth,
          // Decode at the cell width instead of the source resolution; height follows via BoxFit.fitWidth.
          memCacheWidth: constraints.hasBoundedWidth ? (constraints.maxWidth * MediaQuery.devicePixelRatioOf(context)).round() : null,
          placeholder: (context) => _NoPosterCard(model.noPosterText),
          errorWidget: (context) =>
              Container(color: Colors.black12, margin: PosterConstants.imageErrorMargin, child: const Icon(Icons.error)),
        );
      },
    );
  }
}

class _NoPosterCard extends StatelessWidget {
  final String text;

  const _NoPosterCard(this.text);

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(0))),
      margin: PosterConstants.noPosterMargin,
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}
