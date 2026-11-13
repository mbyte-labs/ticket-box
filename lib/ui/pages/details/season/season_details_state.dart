import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:ticketbox/common/model/history_action_type.dart';
import 'package:ticketbox/common/model/item_type.dart';
import 'package:ticketbox/common/model/mark_as_watched_target.dart';
import 'package:ticketbox/common/model/tuple.dart';
import 'package:ticketbox/service/external_rating/external_ratings.dart';
import 'package:ticketbox/service/people/cast_member.dart';
import 'package:ticketbox/service/poster/poster_model.dart';
import 'package:ticketbox/service/title_builder.dart';
import 'package:ticketbox/ui/pages/details/common/details_external_link.dart';
import 'package:ticketbox/ui/pages/details/common/details_load_status.dart';
import 'package:ticketbox/ui/pages/details/common/details_pending_action.dart';
import 'package:ticketbox/ui/pages/details/common/details_watch_provider.dart';
import 'package:ticketbox/ui/pages/details/common/details_watched_status.dart';

part 'season_details_state.freezed.dart';

@freezed
abstract class SeasonDetailsState with _$SeasonDetailsState {
  const factory SeasonDetailsState({
    /// (show TMDB id, season number)
    required Tuple2<int, int> providerId,

    /// The action bar write currently in flight, if any.
    required DetailsPendingAction? pendingAction,
    required bool initialLoading,
    required DetailsLoadStatus loadStatus,
    required bool hasError,
    required String message,

    /// Whether the parent show is in the library.
    required bool tracked,

    /// The season's poster and the show's backdrop, as TMDB relative paths.
    required String? posterPath,
    required String? backdropPath,
    required String? title,

    /// Title of the show this season belongs to (used by the context breadcrumb)
    required String? showTitle,
    required String? overview,
    required DateTime? firstAired,

    /// TMDB community rating for the second row of the Ratings card — for a season this is
    /// derived (the vote-count-weighted average of its episodes); the IMDb half is always
    /// empty because seasons have no IMDb id. Null until the first answer arrives.
    required ExternalRatings? externalRatings,

    /// The network that aired the season
    required String? network,

    /// Meta of the parent show, shown in the season's meta strip
    required String? language,
    required List<String> genres,

    /// Total number of episodes in the season
    required int episodeCount,

    /// Number of episodes that have already aired
    required int airedEpisodes,

    /// Distinct episodes of this season the user has watched at least once. Compared against
    /// [airedEpisodes] — not [episodeCount] — so a still-airing season can read as complete.
    required int watchedEpisodes,

    /// The mean of the user's ratings of this season's episodes (1-10), null while none is rated.
    /// Seasons are not rated directly, so this is what the Ratings card's hearts show.
    required double? episodeRatingAverage,

    /// How many of this season's episodes [episodeRatingAverage] is averaged over.
    required int ratedEpisodes,
    required bool watchListed,
    required bool dropped,

    /// One tile per episode of this season, ordered by episode number, marked with the user's rows.
    required List<PosterModel> episodes,
    required List<CastMember> actorsRegulars,
    required List<CastMember> actorsGuests,
    required List<DetailsExternalLink> externalLinks,

    /// Watch history entries for every episode of this season, newest first
    required List<SeasonWatchEntry> watchedHistory,

    /// Whether the user has picked a streaming country in the settings. While false the
    /// Watch now section renders nothing — the "set your country" nudge lives on the up-next
    /// dashboard instead.
    required bool watchProviderRegionSet,

    /// Subscription services streaming the parent show in the user's country, most relevant
    /// first — the snapshot carries providers at show level only.
    required List<DetailsWatchProvider> watchProviders,

    /// JustWatch offer page opened by tapping any provider logo (the parent show's page). Null
    /// when TMDB has no offer link, which leaves the logos inert.
    String? watchProviderLink,
  }) = _SeasonDetailsState;

  factory SeasonDetailsState.initial(Tuple2<int, int> providerId) {
    return SeasonDetailsState(
      providerId: providerId,
      pendingAction: null,
      initialLoading: true,
      loadStatus: DetailsLoadStatus.loading,
      hasError: false,
      message: '',
      tracked: false,
      posterPath: null,
      backdropPath: null,
      title: null,
      showTitle: null,
      overview: null,
      firstAired: null,
      externalRatings: null,
      network: null,
      language: null,
      genres: [],
      episodeCount: 0,
      airedEpisodes: 0,
      watchedEpisodes: 0,
      episodeRatingAverage: null,
      ratedEpisodes: 0,
      watchListed: false,
      dropped: false,
      episodes: [],
      actorsRegulars: [],
      actorsGuests: [],
      externalLinks: [],
      watchedHistory: [],
      watchProviderRegionSet: false,
      watchProviders: [],
    );
  }
}

extension SeasonDetailsStateActions on SeasonDetailsState {
  /// What the mark-as-watched flow should act on. Always available — the show id and season
  /// number in [providerId] are the whole identity.
  MarkAsWatchedTarget get markAsWatchedTarget {
    return MarkAsWatchedTarget(
      type: ItemType.season,
      showTmdbId: providerId.item1,
      season: providerId.item2,
      title: showTitle ?? '-No title available-',
      subtitle: ConfirmationTitleBuilder.seasonTitle(providerId.item2),
    );
  }

  /// How much of this season has been watched, against the aired count so a still-airing season
  /// can read as complete.
  DetailsWatchedStatus get watchedStatus {
    return DetailsWatchedStatus(
      watched: watchedEpisodes,
      total: airedEpisodes,
      lastWatchedAt: watchedHistory.isEmpty ? null : watchedHistory.first.watchedAt,
    );
  }
}

/// A single entry in the user's watch history for an episode of this season.
///
/// Unlike the episode page's equivalent these entries span the whole season, so
/// each one carries the episode number it belongs to.
@freezed
abstract class SeasonWatchEntry with _$SeasonWatchEntry {
  const factory SeasonWatchEntry({
    required int historyId,
    required int episode,
    required DateTime watchedAt,
    required HistoryAction action,
  }) = _SeasonWatchEntry;
}
