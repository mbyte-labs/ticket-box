import 'package:ticketbox/api/tmdb/image_size_util.dart';
import 'package:ticketbox/common/model/poster_quality_option.dart';
import 'package:ticketbox/database/key_value_store/key_value_store.dart';
import 'package:ticketbox/database/key_value_store/keys/general_properties_keys.dart';
import 'package:ticketbox/service/artwork/artwork_kind.dart';
import 'package:ticketbox/service/artwork/artwork_paths.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';

/// Which TMDB size the library downloads each kind of artwork at, and the URL that follows.
///
/// Posters follow the poster quality preference but stop at `w780`: `original` can be a
/// multi-megabyte scan, and a tracked library keeps every poster for good. Backdrops are always
/// `w1280` (they render full-width behind the details page, so the preference has little to say
/// about them), stills follow the preference's still scale, and cast headshots are always the
/// `w185` the cards render at.
class ArtworkSizes {
  static String sizeFor(ArtworkKind kind, PosterQualityOption quality) => switch (kind) {
    ArtworkKind.poster || ArtworkKind.seasonPoster => _posterSize(quality),
    ArtworkKind.backdrop => TmdbImageSizeUtil.backdropSizeLarge,
    ArtworkKind.still => TmdbImageBuildUtil.getStillImageQuality(quality),
    ArtworkKind.cast => TmdbImageSizeUtil.profileSizeMedium,
  };

  /// The download URL of [ref] at [quality], or null when it has no path or an unsafe one.
  static String? url(ArtworkRef ref, PosterQualityOption quality) =>
      ArtworkPaths.isSafeTmdbPath(ref.tmdbPath) ? TmdbImageBuildUtil.buildUrl(ref.tmdbPath, imageSize: sizeFor(ref.kind, quality)) : null;

  /// The user's poster quality preference (medium until set).
  static Future<PosterQualityOption> preferredQuality() => KeyValueStore.instance().getEnumOrDefault(
    GeneralPropertiesKeys.posterQuality,
    PosterQualityOption.values,
    PosterQualityOption.medium,
  );

  static String _posterSize(PosterQualityOption quality) {
    final size = TmdbImageBuildUtil.getPosterImageQuality(quality);
    return size == TmdbImageSizeUtil.original ? TmdbImageSizeUtil.posterSizeHighest : size;
  }
}
