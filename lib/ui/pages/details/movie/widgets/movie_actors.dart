import 'package:flutter/material.dart';
import 'package:ticketbox/api/tmdb/image_size_util.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/common/details_section.dart';
import 'package:ticketbox/ui/pages/details/movie/movie_details_state.dart';
import 'package:ticketbox/ui/pages/details/person/person_route_args.dart';

/// Cast section: a horizontal actor card list.
///
/// Unlike the show version there is no Regulars/Guests toggle — TMDB bills a
/// movie's whole cast as one list. Always shown; when there is no cast data a
/// placeholder message renders instead. Tapping a card opens that person's
/// details page.
class MovieActors extends StatelessWidget {
  final List<MovieActorData> actors;

  /// The movie the cast belongs to — its artwork directory holds the headshots.
  final MediaKey itemKey;

  const MovieActors({required this.actors, required this.itemKey, super.key});

  @override
  Widget build(BuildContext context) {
    return DetailsSection(
      title: 'Cast',
      child: SizedBox(
        height: ScreenSizeUtil.calculateSize(actors.isEmpty ? 60 : 190),
        width: double.infinity,
        child: actors.isEmpty
            ? Center(
                child: Text(
                  'No actor information available for this movie',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              )
            : ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: actors.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: ScreenSizeUtil.fromLTRB(0, 0, 8, 0),
                    width: ScreenSizeUtil.calculateSize(100),
                    child: _ActorCard(actors[index], itemKey),
                  );
                },
              ),
      ),
    );
  }
}

class _ActorCard extends StatelessWidget {
  final MovieActorData actor;
  final MediaKey itemKey;

  const _ActorCard(this.actor, this.itemKey);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final profilePath = actor.profilePath;

    final fallback = ColoredBox(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Center(child: Icon(Icons.person_outline, color: colorScheme.onSurfaceVariant)),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => PosterNavigation.personNavigateRaw(
        context,
        actor.personTmdbId,
        args: PersonRouteArgs(
          name: actor.name,
          photoUrl: profilePath == null ? null : TmdbImageBuildUtil.buildUrl(profilePath, imageSize: TmdbImageSizeUtil.profileSizeMedium),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: profilePath == null
                    ? fallback
                    : ArtworkImage(
                        ref: ArtworkRef.cast(itemKey, profilePath),
                        fit: BoxFit.cover,
                        // Decode at card width instead of the source resolution; height follows via BoxFit.cover.
                        memCacheWidth: (ScreenSizeUtil.calculateSize(100) * MediaQuery.devicePixelRatioOf(context)).round(),
                        placeholder: (context) => fallback,
                        errorWidget: (context) => fallback,
                      ),
              ),
            ),
          ),
          SizedBox(height: ScreenSizeUtil.calculateSize(6)),
          Text(
            actor.name,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            actor.characterName,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
