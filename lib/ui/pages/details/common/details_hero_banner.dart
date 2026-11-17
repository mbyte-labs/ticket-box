import 'package:material_ui/material_ui.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';

/// Banner image used as the hero app bar background on the details pages, with a
/// scrim that fades the bottom edge into the page surface so the overlaid title
/// stays legible.
///
/// An absent backdrop deliberately renders as a plain surface fill rather than a
/// missing-image placeholder: the bar is built before the page data loads, so a
/// null ref means "still loading" just as often as "no backdrop available", and
/// an icon there would clash with the page loading indicator below it.
class DetailsHeroBanner extends StatelessWidget {
  /// The movie's or show's backdrop; season and episode pages pass the show's.
  final ArtworkRef? backdrop;

  const DetailsHeroBanner(this.backdrop, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ref = backdrop;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (ref == null || ref.tmdbPath == null)
          ColoredBox(color: colorScheme.surface)
        else
          ArtworkImage(
            ref: ref,
            fit: BoxFit.cover,
            // Decode at screen width instead of the source resolution; height follows via BoxFit.cover.
            memCacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round(),
            placeholder: (context) => const Center(child: CircularProgressIndicator()),
            errorWidget: (context) => const Center(child: Icon(Icons.error_outline)),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.35, 0.55, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.5),
                Colors.transparent,
                Colors.transparent,
                colorScheme.surface.withValues(alpha: 0.95),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
