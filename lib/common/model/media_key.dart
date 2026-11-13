import 'package:ticketbox/common/model/item_type.dart';

/// Identifies one movie, show, season or episode by TMDB ids and numbers.
///
/// [tmdbId] is the movie's own id for a movie and the **show's** id for shows, seasons and
/// episodes; seasons and episodes are addressed by number under their show, which is how TMDB
/// itself models them (`/tv/{id}/season/{n}/episode/{e}`). Season and episode are `0` where they do
/// not apply, the same not-applicable sentinel every user-data table uses.
///
/// Movies and shows share TMDB's numeric id space, so [type] is always part of the identity: a
/// movie and a show with the same number are different items.
class MediaKey {
  final ItemType type;
  final int tmdbId;
  final int season;
  final int episode;

  const MediaKey({required this.type, required this.tmdbId, this.season = 0, this.episode = 0});

  const MediaKey.movie(this.tmdbId) : type = ItemType.movie, season = 0, episode = 0;

  const MediaKey.show(this.tmdbId) : type = ItemType.show, season = 0, episode = 0;

  const MediaKey.season(this.tmdbId, this.season) : type = ItemType.season, episode = 0;

  const MediaKey.episode(this.tmdbId, this.season, this.episode) : type = ItemType.episode;

  /// The key of the parent show for a season or episode; the key itself for a show or a movie.
  MediaKey get showKey => switch (type) {
    ItemType.movie || ItemType.show => this,
    ItemType.season || ItemType.episode => MediaKey.show(tmdbId),
  };

  @override
  bool operator ==(Object other) =>
      other is MediaKey && other.type == type && other.tmdbId == tmdbId && other.season == season && other.episode == episode;

  @override
  int get hashCode => Object.hash(type, tmdbId, season, episode);

  @override
  String toString() => switch (type) {
    ItemType.movie => 'movie $tmdbId',
    ItemType.show => 'show $tmdbId',
    ItemType.season => 'show $tmdbId S$season',
    ItemType.episode => 'show $tmdbId S${season}E$episode',
  };
}
