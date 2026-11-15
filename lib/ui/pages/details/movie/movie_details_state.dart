import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/media_ref.dart';
import 'package:ticketbox/common/model/movie_status.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_status.dart';

part 'movie_details_state.freezed.dart';

@freezed
abstract class MovieDetailsState with _$MovieDetailsState {
  const factory MovieDetailsState({
    /// The movie's TMDB id
    required int providerId,

    /// IMDb id, for the external link. Null until the movie has loaded or when TMDB has none.
    required String? imdbId,

    /// The action bar write currently in flight, if any.
    required DetailsPendingAction? pendingAction,
    required bool initialLoading,

    /// Loaded from the snapshot or live, or why not; the page renders [message] for the two
    /// failure values.
    required DetailsLoadStatus loadStatus,
    required bool hasError,
    required String message,

    /// Whether the movie is in the library: its artwork is on disk and every action is local.
    required bool tracked,

    /// TMDB relative paths; the artwork layer resolves them.
    required String? posterPath,
    required String? backdropPath,
    required String? title,
    required int? year,

    /// One-line marketing tagline, rendered above the synopsis
    required String? tagLine,
    required String? overview,
    required DateTime? released,

    /// TMDB popularity score and vote count, shown in the "On TMDB" card. Null until loaded.
    required double? popularity,
    required int? voteCount,

    /// TMDB and IMDb community ratings for the second row of the Ratings card.
    /// Null until the first (cached or fresh) answer arrives.
    required ExternalRatings? externalRatings,
    required String? country,
    required String? certification,
    required MovieStatus status,
    required String? language,
    required List<String> genres,

    /// Runtime in minutes
    required int? runtime,
    required String? trailer,
    required String? homepage,

    /// How many times the user has watched this movie, from the local watch history
    required int userPlays,
    required DateTime? lastWatchedAt,
    required String? userRating,
    required bool watchListed,
    required bool favorite,
    @JsonSerializable(explicitToJson: true) required List<MovieActorData> actors,
    required List<DetailsExternalLink> externalLinks,

    /// Watch history entries for this movie, newest first
    required List<MovieWatchEntry> watchedHistory,

    /// The movies TMDB recommends alongside this one, most relevant first, from the snapshot.
    /// Empty when TMDB has nothing for this movie.
    required List<PosterModel> related,

    /// Whether the user has picked a streaming country in the settings. While false the
    /// Watch now section renders nothing — the "set your country" nudge lives on the up-next
    /// dashboard instead.
    required bool watchProviderRegionSet,

    /// Subscription services streaming this movie in the user's country, most relevant first.
    /// Empty when nothing has loaded yet or the movie has no streaming offer there.
    required List<DetailsWatchProvider> watchProviders,

    /// JustWatch offer page for this movie in the user's country, opened by tapping any provider logo.
    /// Null when TMDB has no offer link, which leaves the logos inert.
    String? watchProviderLink,
  }) = _MovieDetailsState;

  factory MovieDetailsState.initial(int providerId) {
    return MovieDetailsState(
      providerId: providerId,
      imdbId: null,
      pendingAction: null,
      initialLoading: true,
      loadStatus: DetailsLoadStatus.loading,
      hasError: false,
      message: '',
      tracked: false,
      posterPath: null,
      backdropPath: null,
      title: null,
      year: null,
      tagLine: null,
      overview: null,
      released: null,
      popularity: null,
      voteCount: null,
      externalRatings: null,
      country: null,
      certification: null,
      status: MovieStatus.unknown,
      language: null,
      genres: [],
      runtime: null,
      trailer: null,
      homepage: null,
      userPlays: 0,
      lastWatchedAt: null,
      userRating: null,
      watchListed: false,
      favorite: false,
      actors: [],
      externalLinks: [],
      watchedHistory: [],
      related: [],
      watchProviderRegionSet: false,
      watchProviders: [],
    );
  }
}

extension MovieDetailsStateActions on MovieDetailsState {
  /// What the mark-as-watched flow should act on. Always available — a movie's TMDB id is the
  /// page's own [MovieDetailsState.providerId], so nothing has to load first.
  MarkAsWatchedTarget get markAsWatchedTarget {
    return MarkAsWatchedTarget(
      type: ItemType.movie,
      showTmdbId: providerId,
      title: title ?? '-No title available-',
      subtitle: year != null ? 'Movie · $year' : 'Movie',
    );
  }

  MovieRef get ref => MovieRef(tmdbId: providerId, imdbId: imdbId, title: title, year: year);

  /// A movie is watched or not, like an episode — plays beyond the first do not change the state.
  DetailsWatchedStatus get watchedStatus {
    return DetailsWatchedStatus.single(watched: userPlays > 0, lastWatchedAt: lastWatchedAt);
  }
}

/// A single entry in the user's watch history for this movie.
@freezed
abstract class MovieWatchEntry with _$MovieWatchEntry {
  const factory MovieWatchEntry({required int historyId, required DateTime watchedAt, required HistoryAction action}) = _MovieWatchEntry;
}

@freezed
abstract class MovieActorData with _$MovieActorData {
  const factory MovieActorData({required String name, required String characterName, String? profilePath, required int personTmdbId}) =
      _MovieActorData;
}
