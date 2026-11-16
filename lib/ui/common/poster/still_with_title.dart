import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/common/poster/poster_body.dart';
import 'package:ticketbox/ui/theme/constants.dart';

/// Landscape sibling of [PosterWithTitle]: a 16:9 episode still with the same title line and
/// the same pill overlays. The still is the model's own `stillPath`; without one the tile falls
/// through to the shared no-image title card.
class StillWithTitle extends StatelessWidget {
  final PosterModel model;
  final void Function(PosterModel)? onTap;
  final void Function(PosterModel)? onLongPress;

  const StillWithTitle({required this.model, super.key, this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final key = model.key;
    return Column(
      children: [
        AspectRatio(
          aspectRatio: PosterConstants.stillAspectRatio,
          child: GestureDetector(
            onTap: onTap == null ? null : () => onTap!(model),
            onLongPress: onLongPress == null ? null : () => onLongPress!(model),
            child: PosterBody(model, artwork: ArtworkRef.still(key.tmdbId, key.season, key.episode, model.stillPath)),
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
      ],
    );
  }
}
