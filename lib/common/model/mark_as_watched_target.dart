import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/media_key.dart';
import 'package:ticketbox/common/model/media_ref.dart';
import 'package:ticketbox/service/title_builder.dart';

/// Identifies the thing a "mark as watched" flow acts on, so the confirmation modal, its cubit
/// and the history service can be shared across shows, seasons, episodes and movies.
///
/// Every user-data table is keyed on the parent show's TMDB id plus season/episode numbers, so
/// that is what is carried: [showTmdbId] is the show's id for shows, seasons and episodes, and
/// the movie's own id for a movie.
class MarkAsWatchedTarget {
  final ItemType type;

  /// TMDB id of the parent show — or of the movie itself.
  final int showTmdbId;

  /// Season number, or 0 for a show or a movie.
  final int season;

  /// Episode number, or 0 for a show, season or movie.
  final int episode;

  /// Shown as the modal's first line.
  final String title;

  /// Shown as the modal's second, emphasized line.
  final String subtitle;

  const MarkAsWatchedTarget({
    required this.type,
    required this.showTmdbId,
    required this.title,
    required this.subtitle,
    this.season = 0,
    this.episode = 0,
  });

  factory MarkAsWatchedTarget.movie(MovieRef movie) {
    return MarkAsWatchedTarget(
      type: ItemType.movie,
      showTmdbId: movie.tmdbId,
      title: movie.title ?? '-No title available-',
      subtitle: movie.year?.toString() ?? '',
    );
  }

  factory MarkAsWatchedTarget.show(ShowRef show) {
    return MarkAsWatchedTarget(
      type: ItemType.show,
      showTmdbId: show.tmdbId,
      title: ConfirmationTitleBuilder.showTitle(show),
      subtitle: 'Every aired episode',
    );
  }

  factory MarkAsWatchedTarget.season(ShowRef show, SeasonRef season) {
    return MarkAsWatchedTarget(
      type: ItemType.season,
      showTmdbId: show.tmdbId,
      season: season.season,
      title: ConfirmationTitleBuilder.showTitle(show),
      subtitle: ConfirmationTitleBuilder.seasonTitle(season.season),
    );
  }

  factory MarkAsWatchedTarget.episode(ShowRef show, EpisodeRef episode) {
    return MarkAsWatchedTarget(
      type: ItemType.episode,
      showTmdbId: show.tmdbId,
      season: episode.season,
      episode: episode.episode,
      title: ConfirmationTitleBuilder.showTitle(show),
      subtitle: ConfirmationTitleBuilder.episodeTitle(episode),
    );
  }

  MediaKey get key => MediaKey(type: type, tmdbId: showTmdbId, season: season, episode: episode);

  /// Whether the per-episode release-date options are meaningful for this type.
  ///
  /// `WatchedConfirmationDateSelect.seasonReleaseDate` / `episodeReleaseDate` only say something
  /// extra when the target spans multiple episodes; for a single episode its own release date is
  /// already what `releaseDate` means.
  bool get spansMultipleEpisodes => type == ItemType.show || type == ItemType.season;

  /// Whether a live check-in makes sense for this target.
  ///
  /// A check-in is a single playable thing running right now, so only an episode or a movie
  /// qualifies. There is no show- or season-wide form of it.
  bool get supportsCheckIn => type == ItemType.episode || type == ItemType.movie;

  /// Whether the user can give this target a rating of its own.
  ///
  /// A season is never rated directly: its score is the average of the user's episode ratings
  /// (`RatingService.seasonAverage`), so the confirmation hides the rating selector for it.
  bool get supportsRating => type != ItemType.season;
}
