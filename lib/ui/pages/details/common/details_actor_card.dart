import 'package:flutter/material.dart';
import 'package:ticketbox/api/tmdb/image_size_util.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/screen_size_util.dart';
import 'package:ticketbox/ui/common/artwork/artwork_image.dart';
import 'package:ticketbox/ui/common/poster/poster_tap_navigation.dart';
import 'package:ticketbox/ui/pages/details/person/person_route_args.dart';

/// One actor card of a Cast section: the headshot from the owning item's artwork directory (or
/// the browse cache for an untracked item), the name and the character(s). Tapping it opens the
/// person's page.
class DetailsActorCard extends StatelessWidget {
  final CastMember actor;

  /// The movie or show the cast belongs to — its artwork directory holds the headshots.
  final MediaKey itemKey;

  const DetailsActorCard({required this.actor, required this.itemKey, super.key});

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
