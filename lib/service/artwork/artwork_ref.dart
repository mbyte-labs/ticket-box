import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/service/artwork/artwork_kind.dart';

/// One piece of artwork: which item it belongs to, what kind it is, and TMDB's path for it.
///
/// [item] is always the owning movie or show; a season poster or an episode still carries its
/// [season] / [episode] numbers next to it, the way `MediaKey` addresses them under their show.
/// [tmdbPath] is TMDB's `/abc.jpg` (or null when the title has none): it decides the download
/// URL, never the file name on disk, which is fixed per kind.
class ArtworkRef {
  final MediaKey item;
  final ArtworkKind kind;
  final int season;
  final int episode;
  final String? tmdbPath;

  const ArtworkRef._({required this.item, required this.kind, this.season = 0, this.episode = 0, required this.tmdbPath});

  const ArtworkRef.poster(MediaKey item, String? path) : this._(item: item, kind: ArtworkKind.poster, tmdbPath: path);

  const ArtworkRef.backdrop(MediaKey item, String? path) : this._(item: item, kind: ArtworkKind.backdrop, tmdbPath: path);

  ArtworkRef.seasonPoster(int showTmdbId, this.season, this.tmdbPath)
    : item = MediaKey.show(showTmdbId),
      kind = ArtworkKind.seasonPoster,
      episode = 0;

  ArtworkRef.still(int showTmdbId, this.season, this.episode, this.tmdbPath) : item = MediaKey.show(showTmdbId), kind = ArtworkKind.still;

  const ArtworkRef.cast(MediaKey item, String? profilePath) : this._(item: item, kind: ArtworkKind.cast, tmdbPath: profilePath);

  /// The poster a tile for [key] shows: the title's own for a movie or a show, the season's for a
  /// season, and the season's for an episode too — an episode tile shows its season poster.
  factory ArtworkRef.fromPosterKey(MediaKey key, String? posterPath) => switch (key.type) {
    ItemType.movie || ItemType.show => ArtworkRef.poster(key, posterPath),
    ItemType.season || ItemType.episode => ArtworkRef.seasonPoster(key.tmdbId, key.season, posterPath),
  };

  @override
  bool operator ==(Object other) =>
      other is ArtworkRef &&
      other.item == item &&
      other.kind == kind &&
      other.season == season &&
      other.episode == episode &&
      other.tmdbPath == tmdbPath;

  @override
  int get hashCode => Object.hash(item, kind, season, episode, tmdbPath);

  @override
  String toString() => switch (kind) {
    ArtworkKind.seasonPoster => 'season poster of $item S$season ($tmdbPath)',
    ArtworkKind.still => 'still of $item S${season}E$episode ($tmdbPath)',
    ArtworkKind.poster || ArtworkKind.backdrop || ArtworkKind.cast => '${kind.name} of $item ($tmdbPath)',
  };
}
