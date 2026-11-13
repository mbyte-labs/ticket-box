import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_ref.dart';
import 'package:ticketbox/service/stats/stats_models.dart';

/// The [ArtworkRef]s of the titles the stats page names, from the bloc's artwork map. Null while
/// the title's entry is not loaded yet, so the widgets draw their placeholder; an entry whose
/// path is null gives a ref the image resolves to the placeholder too.
extension StatsArtworkRefs on Map<MediaKey, TitleArtwork> {
  /// The poster of the movie or show [key].
  ArtworkRef? posterOf(MediaKey key) {
    final artwork = this[key];
    return artwork == null ? null : ArtworkRef.poster(key, artwork.posterPath);
  }

  /// The backdrop of [key]'s movie or show (a season or episode key draws its show's).
  ArtworkRef? bannerOf(MediaKey key) {
    final artwork = this[key];
    return artwork == null ? null : ArtworkRef.backdrop(key.showKey, artwork.backdropPath);
  }
}
